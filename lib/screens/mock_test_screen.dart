import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/question.dart';
import '../config/mock_test_config.dart';
import '../config/app_strings.dart';
import '../providers/user_state_provider.dart';
import '../widgets/question_widget.dart';
import 'mock_test_result_screen.dart';

/// 模擬考試頁面
/// 實現 30題、20分鐘、錯3題合格的考試邏輯
class MockTestScreen extends StatefulWidget {
  const MockTestScreen({super.key});

  @override
  State<MockTestScreen> createState() => _MockTestScreenState();
}

class _MockTestScreenState extends State<MockTestScreen> {
  List<Question> _questions = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  final List<String> _errorIds = [];
  Timer? _timer;
  int _timeRemaining = MockTestConfig.timeLimitSeconds; // 轉換為秒
  
  // 當前語言（從 Provider 獲取）
  String get _currentLanguage {
    return Provider.of<UserStateProvider>(context, listen: false).currentLanguage;
  }

  @override
  void initState() {
    super.initState();
    _startMockTest();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 開始模擬考試
  Future<void> _startMockTest() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 使用与练习模式相同的方法：使用 getQuestions 获取所有题目，然后随机选择
      // 先获取所有意大利语题目
      final allItalianQuestions = await DatabaseService.getQuestions(lang: 'it');
      if (allItalianQuestions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${AppStrings.get('failed_to_load')}: 数据库中没有意大利语题目')),
          );
          Navigator.pop(context);
        }
        return;
      }
      
      // 随机打乱并选择30个
      allItalianQuestions.shuffle();
      final selectedItalianQuestions = allItalianQuestions.take(MockTestConfig.totalQuestions).toList();
      
      // 如果当前语言不是意大利语，获取翻译并合并
      final allQuestions = <Question>[];
      if (_currentLanguage != 'it') {
        for (final questionIt in selectedItalianQuestions) {
          try {
            final translatedQuestion = await DatabaseService.getQuestionById(
              questionIt.id,
              lang: _currentLanguage,
            );
            if (translatedQuestion != null) {
              allQuestions.add(questionIt.mergeLanguages(translatedQuestion));
            } else {
              // 如果翻译不存在，只使用意大利语题目
              allQuestions.add(questionIt);
            }
          } catch (e) {
            // 如果获取翻译失败，使用原始意大利语题目
            allQuestions.add(questionIt);
          }
        }
      } else {
        allQuestions.addAll(selectedItalianQuestions);
      }
      
      if (allQuestions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStrings.get('failed_to_load'))),
          );
          Navigator.pop(context);
        }
        return;
      }
      
      final questions = allQuestions;

      // getMockTestQuestions 已經返回包含意大利語和翻譯的題目，直接使用
      setState(() {
        _questions = questions;
        _currentIndex = 0;
        _errorIds.clear();
        _timeRemaining = MockTestConfig.timeLimitSeconds;
        _isLoading = false;
      });

      _startTimer();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.get('failed_to_load')}: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  /// 啟動倒計時計時器
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_timeRemaining > 0) {
          _timeRemaining--;
        } else {
          // 時間到
          timer.cancel();
          _finishTest();
        }
      });
    });
  }

  /// 處理答案選擇
  Future<void> _onAnswerSelected(bool selectedAnswer) async {
    if (_currentIndex >= _questions.length) return;

    final question = _questions[_currentIndex];
    final isCorrect = selectedAnswer == question.answer;

    if (!isCorrect && !_errorIds.contains(question.id)) {
      _errorIds.add(question.id);
      // 記錄錯誤到數據庫（模擬考試模式：只記錄錯誤，不影響 correct_streak）
      await DatabaseService.recordErrorInExam(question.id);
    }

      // 顯示結果提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCorrect 
              ? AppStrings.get('correct_answer') 
              : AppStrings.get('wrong_answer')),
          backgroundColor: isCorrect ? Colors.green : Colors.red,
          duration: const Duration(milliseconds: 700),
        ),
      );

    // 延遲後下一題或完成考試
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;

      setState(() {
        _currentIndex++;
      });

      if (_currentIndex >= _questions.length) {
        _finishTest();
      }
    });
  }

  /// 完成考試並跳轉到結果頁面
  void _finishTest() {
    _timer?.cancel();
    
    if (!mounted) return;

    final correctAnswers = _questions.length - _errorIds.length;
    final isPassed = _errorIds.length <= MockTestConfig.maxErrors;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => MockTestResultScreen(
          totalQuestions: _questions.length,
          correctAnswers: correctAnswers,
          errors: _errorIds.length,
          isPassed: isPassed,
          timeRemaining: _timeRemaining,
          errorIds: _errorIds,
        ),
      ),
    );
  }

  /// 格式化時間顯示（MM:SS）
  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// 計算時間進度百分比
  double _getTimeProgress() {
    return _timeRemaining / MockTestConfig.timeLimitSeconds;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 如果題目列表為空，顯示錯誤提示而不是"考試完成"
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(AppStrings.get('mock_test_title')),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                AppStrings.get('failed_to_load'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.get('cannot_get_enough_questions'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.get('return_home')),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentIndex >= _questions.length) {
      return Scaffold(
        body: Center(child: Text(AppStrings.get('mock_test_completed'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('mock_test_title')),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // 倒計時顯示欄
          Container(
            padding: const EdgeInsets.all(16),
            color: _timeRemaining < 300 ? Colors.red[100] : Colors.blue[50],
            child: Column(
              children: [
                Text(
                  '${AppStrings.get('time_remaining')}: ${_formatTime(_timeRemaining)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _timeRemaining < 300 ? Colors.red[900] : Colors.blue[900],
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _getTimeProgress(),
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _timeRemaining < 300 ? Colors.red : Colors.blue,
                  ),
                ),
              ],
            ),
          ),

          // 題目內容
          Expanded(
            child: QuestionWidget(
              question: _questions[_currentIndex],
              onAnswerSelected: _onAnswerSelected,
              currentLanguage: _currentLanguage,
              currentIndex: _currentIndex,
              totalQuestions: _questions.length,
              isExamMode: true, // 考試模式
            ),
          ),
        ],
      ),
    );
  }
}
