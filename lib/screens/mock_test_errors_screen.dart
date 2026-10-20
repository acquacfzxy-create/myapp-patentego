import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/question.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../providers/user_state_provider.dart';
import '../widgets/question_widget.dart';

/// 模擬考試錯題查看頁面
/// 顯示本套模擬考試的所有錯題
class MockTestErrorsScreen extends StatefulWidget {
  /// 錯誤題目的ID列表
  final List<String> errorIds;

  const MockTestErrorsScreen({
    super.key,
    required this.errorIds,
  });

  @override
  State<MockTestErrorsScreen> createState() => _MockTestErrorsScreenState();
}

class _MockTestErrorsScreenState extends State<MockTestErrorsScreen> {
  List<Question> _errorQuestions = [];
  bool _isLoading = true;
  int _currentIndex = 0;

  // 當前語言（從 Provider 獲取）
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
      // 獲取錯題的完整信息（包含意大利語和翻譯）
      final questions = <Question>[];

      for (final id in widget.errorIds) {
        // 先獲取意大利語題目
        final questionIt =
            await DatabaseService.getQuestionById(id, lang: 'it');
        if (questionIt != null) {
          // 如果當前語言不是意大利語，獲取翻譯並合併
          if (_currentLanguage != 'it') {
            final translatedQuestion = await DatabaseService.getQuestionById(id,
                lang: _currentLanguage);
            if (translatedQuestion != null) {
              questions.add(questionIt.mergeLanguages(translatedQuestion));
            } else {
              questions.add(questionIt);
            }
          } else {
            questions.add(questionIt);
          }
        }
      }

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

  /// 處理答案選擇（只顯示，不記錄）
  void _onAnswerSelected(bool selectedAnswer) {
    if (_currentIndex >= _errorQuestions.length) return;

    final question = _errorQuestions[_currentIndex];
    final isCorrect = selectedAnswer == question.answer;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCorrect
              ? AppStrings.get('correct_answer')
              : AppStrings.get('wrong_answer')),
          backgroundColor: isCorrect
              ? AppTheme.successFor(context)
              : AppTheme.dangerFor(context),
          duration: const Duration(milliseconds: 700),
        ),
      );
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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      // 頁面底色由主題提供，內容較短時也不會露出黑色窗口底。
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(AppStrings.get('view_test_errors')),
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: AppTheme.pageDecorationFor(context),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorQuestions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 88,
                          color: AppTheme.successFor(context),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          AppStrings.get('no_mistakes'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceFor(context),
                          border: Border(
                            bottom: BorderSide(
                              color: AppTheme.lineFor(context),
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              tooltip: MaterialLocalizations.of(context)
                                  .previousPageTooltip,
                              icon: const Icon(Icons.arrow_back),
                              onPressed:
                                  _currentIndex > 0 ? _previousQuestion : null,
                            ),
                            Text(
                              '${_currentIndex + 1} / ${_errorQuestions.length}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            IconButton(
                              tooltip: MaterialLocalizations.of(context)
                                  .nextPageTooltip,
                              icon: const Icon(Icons.arrow_forward),
                              onPressed:
                                  _currentIndex < _errorQuestions.length - 1
                                      ? _nextQuestion
                                      : null,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: QuestionWidget(
                          question: _errorQuestions[_currentIndex],
                          onAnswerSelected: _onAnswerSelected,
                          currentLanguage: _currentLanguage,
                          currentIndex: _currentIndex,
                          totalQuestions: _errorQuestions.length,
                          isExamMode: false,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
