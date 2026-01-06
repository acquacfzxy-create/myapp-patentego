import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/question.dart';
import '../config/app_strings.dart';
import '../providers/user_state_provider.dart';
import '../widgets/question_widget.dart';

/// 練習模式頁面
/// 支持順序練習，顯示題目、圖片、解析等功能
class PracticeScreen extends StatefulWidget {
  final bool skipMastered;
  final int? chapterId; // 章節ID（可選），如果提供則只顯示該章節的題目
  
  const PracticeScreen({
    super.key,
    this.skipMastered = false,
    this.chapterId,
  });

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  Question? _currentQuestion;
  bool _isLoading = true;
  int _totalAnswered = 0;
  int _errors = 0;
  final List<String> _errorIds = [];
  late bool _skipMastered; // 使用 State 變量來管理，以便在運行時切換
  
  // 章節練習模式：預加載的題目列表（優化性能，避免每次都查詢數據庫）
  List<Question>? _chapterQuestions;
  int _currentIndex = 0; // 當前題目在列表中的索引
  
  // 掌握度統計更新延遲（避免頻繁查詢數據庫）
  DateTime? _lastMasteryStatsUpdate;
  static const Duration _masteryStatsUpdateInterval = Duration(seconds: 2);
  
  // 當前語言（從 Provider 獲取，向後兼容 AppStrings）
  String get _currentLanguage => 
      Provider.of<UserStateProvider>(context, listen: false).currentLanguage;

  @override
  void initState() {
    super.initState();
    _skipMastered = widget.skipMastered;
    _initializeQuestions();
  }
  
  /// 初始化題目列表（章節練習模式預加載，隨機模式動態加載）
  Future<void> _initializeQuestions() async {
    if (widget.chapterId != null) {
      // 章節練習模式：預加載整個章節的題目列表
      await _loadChapterQuestions();
    } else {
      // 隨機模式：動態加載單題
      _loadQuestion();
    }
  }
  
  /// 預加載章節題目列表（只在初始化時調用一次）
  Future<void> _loadChapterQuestions() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      if (kDebugMode) {
        print('📚 [PracticeScreen] 開始預加載章節 ${widget.chapterId} 的題目列表...');
      }
      final questions = await DatabaseService.getQuestionsByChapter(
        widget.chapterId!,
        skipMastered: _skipMastered,
        translationLang: _currentLanguage != 'it' ? _currentLanguage : 'it',
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
      
      if (kDebugMode) {
        print('✅ [PracticeScreen] 章節題目列表預加載完成，共 ${questions.length} 道題目');
      }
      
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
  Future<void> _loadQuestion() async {
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
        );
      } else {
        // 隨機模式：先獲取意大利語題目，再獲取翻譯
        // 使用 getQuestions 並傳遞 skipMastered 參數
        final allQuestions = await DatabaseService.getQuestions(
          lang: 'it',
          skipMastered: _skipMastered,
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

  /// 顯示全部已掌握對話框
  Future<void> _showAllMasteredDialog() async {
    if (!mounted) return;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppStrings.get('all_questions_mastered')),
          content: Text(AppStrings.get('all_questions_mastered')),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // 取消，返回上一頁
              },
              child: Text(AppStrings.get('cancel')),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true); // 確認，切換到重溫模式
              },
              child: Text(AppStrings.get('review_mastered')),
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
    if (_currentQuestion == null) return;

    final isCorrect = selectedAnswer == _currentQuestion!.answer;
    
    setState(() {
      _totalAnswered++;
      
      if (!isCorrect) {
        if (!_errorIds.contains(_currentQuestion!.id)) {
          _errorIds.add(_currentQuestion!.id);
          _errors++;
        }
      }
    });

    // 使用統一的進度更新方法
    // 注意：updateQuestionProgress 已經使用事務，且查詢只針對單個題目（WHERE question_id = ?），性能良好
    // 使用 PRIMARY KEY 索引，查詢速度很快
    final newlyMastered = await DatabaseService.updateQuestionProgress(
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
      Provider.of<UserStateProvider>(context, listen: false)
          .refreshMasteryStats()
          .catchError((e) {
        if (kDebugMode) {
          print('⚠️ [PracticeScreen] 更新掌握度統計失敗: $e');
        }
      });
    }

    // 如果剛剛達成掌握，播放觸感反饋
    if (newlyMastered) {
      HapticFeedback.lightImpact();
    }

    // 顯示結果提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCorrect 
              ? AppStrings.get('correct_answer') 
              : AppStrings.get('wrong_answer')),
          backgroundColor: isCorrect ? Colors.green : Colors.red,
          duration: const Duration(milliseconds: 700),
        ),
      );

      // 如果剛剛達成掌握，顯示額外的 Toast 提示
      if (newlyMastered) {
        Future.delayed(const Duration(milliseconds: 750), () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppStrings.get('question_mastered')),
                backgroundColor: Colors.blue,
                duration: const Duration(milliseconds: 1500),
              ),
            );
          }
        });
      }
    }

    // 延遲後切換到下一題
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _nextQuestion();
      }
    });
  }
  
  /// 切換到下一題（優化：章節練習使用索引切換，不重新查詢數據庫）
  void _nextQuestion() {
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
      // 隨機模式：重新加載題目
      _loadQuestion();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('practice_mode_title')),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentQuestion == null
              ? Center(child: Text(AppStrings.get('failed_to_load_question')))
              : Column(
                  children: [
                    // 統計信息欄
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.grey[200],
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text(
                            '${AppStrings.get('questions_answered')}: $_totalAnswered',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${AppStrings.get('errors')}: $_errors',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 題目內容
                    Expanded(
                      child: QuestionWidget(
                        question: _currentQuestion!,
                        onAnswerSelected: _onAnswerSelected,
                        currentLanguage: _currentLanguage,
                        isExamMode: false, // 練習模式
                      ),
                    ),
                  ],
                ),
    );
  }
}
