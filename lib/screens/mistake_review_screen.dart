import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/question.dart';
import '../config/app_strings.dart';
import '../providers/user_state_provider.dart';
import '../widgets/question_widget.dart';

/// 錯題回顧頁面
/// 顯示用戶之前做錯的題目列表
class MistakeReviewScreen extends StatefulWidget {
  const MistakeReviewScreen({super.key});

  @override
  State<MistakeReviewScreen> createState() => _MistakeReviewScreenState();
}

class _MistakeReviewScreenState extends State<MistakeReviewScreen> {
  List<Question> _errorQuestions = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  
  // 當前語言（從 Provider 獲取，向後兼容 AppStrings）
  String get _currentLanguage => 
      Provider.of<UserStateProvider>(context, listen: false).currentLanguage;

  @override
  void initState() {
    super.initState();
    _loadErrorQuestions();
  }

  /// 加載錯題列表
  Future<void> _loadErrorQuestions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final questions = await DatabaseService.getWrongQuestions(
        lang: _currentLanguage,
      );
      
      setState(() {
        _errorQuestions = questions;
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

  /// 處理答案選擇（在錯題回顧中，記錄重新練習的結果）
  void _onAnswerSelected(bool selectedAnswer) async {
    if (_currentIndex >= _errorQuestions.length) return;

    final question = _errorQuestions[_currentIndex];
    final isCorrect = selectedAnswer == question.answer;

    if (isCorrect) {
      // 答對了：清除該題目的錯誤計數，標記為已掌握
      await DatabaseService.clearErrorCount(question.id);
      
      // 從當前列表中移除這道題（因為已經掌握了）
      setState(() {
        _errorQuestions.removeAt(_currentIndex);
        // 如果當前索引超出範圍，調整到最後一題
        if (_currentIndex >= _errorQuestions.length && _errorQuestions.isNotEmpty) {
          _currentIndex = _errorQuestions.length - 1;
        } else if (_errorQuestions.isEmpty) {
          _currentIndex = 0;
        }
      });

      // 顯示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.get('correct_answer')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } else {
      // 答錯了：增加錯誤計數
      await DatabaseService.recordError(question.id);
      
      // 顯示錯誤提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.get('wrong_answer')),
            backgroundColor: Colors.red,
            duration: const Duration(milliseconds: 700),
          ),
        );
      }
    }
  }

  /// 切換到下一題
  void _nextQuestion() {
    if (_currentIndex < _errorQuestions.length - 1) {
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
        title: Text(AppStrings.get('mistake_review')),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorQuestions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 100,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        AppStrings.get('no_mistakes'),
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
                            '${_currentIndex + 1} / ${_errorQuestions.length}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: _currentIndex < _errorQuestions.length - 1
                                ? _nextQuestion
                                : null,
                          ),
                        ],
                      ),
                    ),
                    // 題目內容
                    Expanded(
                      child: QuestionWidget(
                        question: _errorQuestions[_currentIndex],
                        onAnswerSelected: _onAnswerSelected,
                        currentLanguage: _currentLanguage,
                        currentIndex: _currentIndex,
                        totalQuestions: _errorQuestions.length,
                        isExamMode: false, // 練習模式
                      ),
                    ),
                  ],
                ),
    );
  }
}

