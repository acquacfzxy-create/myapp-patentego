import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/question.dart';
import '../config/app_strings.dart';
import '../widgets/question_widget.dart';
import '../providers/user_state_provider.dart';

/// 收藏題目回顧頁面
/// 顯示用戶收藏的題目列表
class FavoriteReviewScreen extends StatefulWidget {
  const FavoriteReviewScreen({super.key});

  @override
  State<FavoriteReviewScreen> createState() => _FavoriteReviewScreenState();
}

class _FavoriteReviewScreenState extends State<FavoriteReviewScreen> {
  List<Question> _favoriteQuestions = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  
  // 當前語言（從 Provider 獲取）
  String get _currentLanguage => Provider.of<UserStateProvider>(context, listen: false).currentLanguage;

  @override
  void initState() {
    super.initState();
    _loadFavoriteQuestions();
  }

  /// 加載收藏題目列表
  Future<void> _loadFavoriteQuestions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final favoriteIds = await DatabaseService.getFavoriteQuestionIds();
      
      if (favoriteIds.isEmpty) {
        setState(() {
          _favoriteQuestions = [];
          _currentIndex = 0;
          _isLoading = false;
        });
        return;
      }

      // 獲取收藏題目的完整信息
      final questions = <Question>[];
      for (final id in favoriteIds) {
        // 先獲取意大利語題目
        final question = await DatabaseService.getQuestionById(id, lang: 'it');
        if (question != null) {
          // 如果當前語言不是意大利語，獲取翻譯並合併
          if (_currentLanguage != 'it') {
            final translatedQuestion = await DatabaseService.getQuestionById(id, lang: _currentLanguage);
            if (translatedQuestion != null) {
              questions.add(question.mergeLanguages(translatedQuestion));
            } else {
              questions.add(question);
            }
          } else {
            questions.add(question);
          }
        }
      }
      
      setState(() {
        _favoriteQuestions = questions;
        _currentIndex = 0;
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

  /// 處理答案選擇
  void _onAnswerSelected(bool selectedAnswer) {
    if (_currentIndex >= _favoriteQuestions.length) return;

    final question = _favoriteQuestions[_currentIndex];
    final isCorrect = selectedAnswer == question.answer;

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
    }
  }

  /// 切換到下一題
  void _nextQuestion() {
    if (_currentIndex < _favoriteQuestions.length - 1) {
      setState(() {
        _currentIndex++;
      });
    }
  }

  /// 切換到上一題
  void _previousQuestion() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('favorite_questions')),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favoriteQuestions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.favorite_border,
                        size: 100,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        AppStrings.get('no_favorites'),
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 題目進度和導航
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.grey[200],
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: _currentIndex > 0 ? _previousQuestion : null,
                          ),
                          Text(
                            '${_currentIndex + 1} / ${_favoriteQuestions.length}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: _currentIndex < _favoriteQuestions.length - 1
                                ? _nextQuestion
                                : null,
                          ),
                        ],
                      ),
                    ),
                    // 題目內容
                    Expanded(
                      child: QuestionWidget(
                        question: _favoriteQuestions[_currentIndex],
                        onAnswerSelected: _onAnswerSelected,
                        currentLanguage: _currentLanguage,
                        currentIndex: _currentIndex,
                        totalQuestions: _favoriteQuestions.length,
                        isExamMode: false, // 練習模式
                      ),
                    ),
                  ],
                ),
    );
  }
}

