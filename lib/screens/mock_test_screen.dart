import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:ui';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/question.dart';
import '../config/mock_test_config.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../providers/user_state_provider.dart';
import 'mock_test_result_screen.dart';
import 'home_screen.dart';

/// 模擬考試頁面
/// 實現 30題、20分鐘、錯3題合格的考試邏輯
class MockTestScreen extends StatefulWidget {
  const MockTestScreen({super.key});

  @override
  State<MockTestScreen> createState() => _MockTestScreenState();
}

class _MockTestScreenState extends State<MockTestScreen> {
  List<Question> _questions = [];
  bool _isLoading = true;
  final List<String> _errorIds = [];
  Timer? _timer;
  int _timeRemaining = MockTestConfig.timeLimitSeconds; // 轉換為秒

  // 答案狀態管理：存儲每道題的用戶選擇（索引 -> selectedAnswer, null表示未選擇）
  final Map<int, bool?> userChoices = {};

  // 當前語言（從 Provider 獲取）
  String get _currentLanguage {
    return Provider.of<UserStateProvider>(context, listen: false)
        .currentLanguage;
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
    // 記錄模擬考試開始（標記今日已使用模擬考）
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    await userStateProvider.setExamUsedToday(true);

    setState(() {
      _isLoading = true;
    });

    try {
      // 使用与练习模式相同的方法：使用 getQuestions 获取所有题目，然后随机选择
      // 先获取所有意大利语题目
      final allItalianQuestions =
          await DatabaseService.getQuestions(lang: 'it');
      if (allItalianQuestions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppStrings.get('failed_to_load')}: ${AppStrings.get('cannot_get_enough_questions')}',
              ),
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      // 随机打乱并选择30个
      allItalianQuestions.shuffle();
      final selectedItalianQuestions =
          allItalianQuestions.take(MockTestConfig.totalQuestions).toList();

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

  /// 處理答案選擇（模擬考試模式：只記錄選擇，不顯示反饋）
  /// [questionIndex] 題目在列表中的索引
  /// [selectedAnswer] 用戶選擇的答案
  /// 靜默更新學習進度：無論是否為考試模式，都要記錄到學習進度中
  void _onAnswerSelected(int questionIndex, bool selectedAnswer) {
    if (questionIndex >= _questions.length) return;

    // 使用索引作為 key 記錄答案狀態，不顯示反饋
    setState(() {
      userChoices[questionIndex] = selectedAnswer;
    });

    // 靜默更新學習進度：判斷用戶選擇是否正確，並更新到數據庫
    final question = _questions[questionIndex];
    final isCorrect = selectedAnswer == question.answer;

    // 後台立即更新學習進度（不阻塞UI，不顯示反饋）
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    userStateProvider
        .updateQuestionProgress(
      question.id,
      isCorrect,
    )
        .catchError((e) {
      // 忽略錯誤，不影響用戶體驗
      // 在調試模式下可以打印錯誤
      if (kDebugMode) {}
      return false; // catchError 需要返回值
    });
  }

  /// 計算已答題數（userChoices 中非 null 的數量）
  int get _answeredCount =>
      userChoices.values.where((answer) => answer != null).length;

  /// 檢查是否所有題目都已作答
  bool get _allQuestionsAnswered =>
      _answeredCount >= MockTestConfig.totalQuestions;

  /// 完成考試並跳轉到結果頁面
  Future<void> _finishTest() async {
    _timer?.cancel();

    if (!mounted) return;

    // 計算錯誤答案：遍歷所有題目，檢查用戶選擇是否正確
    // 未作答的題目計為錯誤
    final errorIds = <String>[];
    for (int i = 0; i < _questions.length; i++) {
      final question = _questions[i];
      final userAnswer = userChoices[i];

      // 未作答或答錯都計為錯誤
      if (userAnswer == null || userAnswer != question.answer) {
        errorIds.add(question.id);
        // 記錄錯誤到數據庫（模擬考試模式：只記錄錯誤，不影響 correct_streak）
        final userStateProvider =
            Provider.of<UserStateProvider>(context, listen: false);
        DatabaseService.recordErrorInExam(
          question.id,
          userId: userStateProvider.effectiveUserId,
        ).catchError((e) {
          // 忽略錯誤，不影響用戶體驗
        });
      }
    }

    final correctAnswers = _questions.length - errorIds.length;
    final isPassed = errorIds.length <= MockTestConfig.maxErrors;

    // 在跳轉到結果頁之前，更新掌握度統計
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    try {
      await userStateProvider.updateMasteryStats();
    } catch (_) {
      // 統計刷新失敗不影響本次模擬考結果展示。
    }

    // 將本次模擬考結果寫入 mock_exam_results，供學習數據中心趨勢圖使用
    try {
      final timeUsedSeconds = MockTestConfig.timeLimitSeconds - _timeRemaining;
      await DatabaseService.saveMockTestResult(
        userId: userStateProvider.effectiveUserId,
        correctCount: correctAnswers,
        wrongCount: errorIds.length,
        totalQuestions: _questions.length,
        timeUsedSeconds: timeUsedSeconds,
      );
    } catch (_) {
      // 歷史成績保存失敗不阻塞結果頁。
    }

    if (!mounted) return;
    await userStateProvider.syncProgressToCloudIfVip();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => MockTestResultScreen(
          totalQuestions: _questions.length,
          correctAnswers: correctAnswers,
          errors: errorIds.length,
          isPassed: isPassed,
          timeRemaining: _timeRemaining,
          errorIds: errorIds,
          questions: _questions, // 傳遞所有題目
          userChoices: userChoices, // 傳遞用戶答案記錄
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

  /// 構建毛玻璃 AppBar
  PreferredSizeWidget _buildGlassAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              border: Border(
                bottom: BorderSide(
                  color: Colors.black.withOpacity(0.05),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 左側：返回按鈕（返回到主頁）
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      color: const Color(0xFF475569),
                      onPressed: () {
                        // 如果導航棧中只有當前頁面，則返回到主頁
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          // 如果沒有上一頁，則返回到主頁
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const HomeScreen(),
                            ),
                          );
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    // 中間：標題 + 小字
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppStrings.get('mock_test_title'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0D131B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'PATENTE B',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 右側：倒計時（淺藍色帶邊框的小盒子）
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF), // bg-blue-50
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFBFDBFE)
                              .withOpacity(0.5), // blue-200
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _formatTime(_timeRemaining),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace', // 電子表字體
                          letterSpacing: 1,
                          color: _timeRemaining < 300
                              ? Colors.red[900]
                              : const Color(0xFF1E40AF), // blue-800
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 構建題目卡片
  Widget _buildQuestionCard(int index) {
    final question = _questions[index];
    final selectedAnswer = userChoices[index];
    final questionText = question.getDisplayQuestionText(
      defaultText: AppStrings.get('question_content_missing'),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頂部行：題號徽章 + 圖片 + 題目文本
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 題號圓形徽章
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 題庫圖片（固定 64x64 或 80x80，圓角包裹，可點擊查看大圖）
                if (question.imageName != null &&
                    question.imageName!.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showImagePreview(question.imageName!),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            color: Colors.grey[100],
                            child: _buildQuestionImage(question.imageName!),
                          ),
                          // 放大鏡圖標（右上角）
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                Icons.zoom_in,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (question.imageName != null &&
                    question.imageName!.isNotEmpty)
                  const SizedBox(width: 12),
                // 意語題目文本（Expanded 包裹）
                Expanded(
                  child: Text(
                    questionText,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      color: Color(0xFF1A1C1E),
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // 底部操作行：VERO 和 FALSO 按鈕
          Container(
            height: 56,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.grey[200]!,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                // VERO 按鈕（左半邊）- 考試模式下選中時保持藍色
                Expanded(
                  child: GestureDetector(
                    onTap: () => _onAnswerSelected(index, true),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selectedAnswer == true
                            ? const Color(0xFF3B82F6) // 藍色（不管對錯）
                            : Colors.white,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(22),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'VERO',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: selectedAnswer == true
                                ? Colors.white
                                : const Color(0xFF1E263C),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 垂直細線分隔
                Container(
                  width: 1,
                  color: Colors.grey[300],
                ),
                // FALSO 按鈕（右半邊）- 考試模式下選中時保持藍色
                Expanded(
                  child: GestureDetector(
                    onTap: () => _onAnswerSelected(index, false),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selectedAnswer == false
                            ? const Color(0xFF3B82F6) // 藍色（不管對錯）
                            : Colors.white,
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(22),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'FALSO',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: selectedAnswer == false
                                ? Colors.white
                                : const Color(0xFF1E263C),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 構建題目圖片
  Widget _buildQuestionImage(String imagePath) {
    // 處理圖片路徑：如果是網絡URL則使用 Image.network，否則嘗試從 assets 加載
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.contain,
        width: 64,
        height: 64,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.image_not_supported,
              size: 32, color: Colors.grey);
        },
      );
    } else {
      // 本地路徑，嘗試從 assets 加載
      String assetPath = imagePath;
      if (assetPath.startsWith('/')) {
        assetPath = assetPath.substring(1);
      }
      if (assetPath.startsWith('img_sign/')) {
        assetPath = 'images/$assetPath';
      }
      return Image.asset(
        assetPath,
        fit: BoxFit.contain,
        width: 64,
        height: 64,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.image_not_supported,
              size: 32, color: Colors.grey);
        },
      );
    }
  }

  /// 顯示圖片預覽（點擊小圖查看大圖）
  void _showImagePreview(String imagePath) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      barrierDismissible: true, // 允許點擊外部關閉
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(), // 點擊任意位置（包括圖片）關閉
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 3.0,
            child: _buildLargeImage(imagePath),
          ),
        ),
      ),
    );
  }

  /// 構建大圖顯示
  Widget _buildLargeImage(String imagePath) {
    // 處理圖片路徑：如果是網絡URL則使用 Image.network，否則嘗試從 assets 加載
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image_not_supported,
                    size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  AppStrings.get('image_load_failed'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        },
      );
    } else {
      // 本地路徑，嘗試從 assets 加載
      String assetPath = imagePath;
      if (assetPath.startsWith('/')) {
        assetPath = assetPath.substring(1);
      }
      if (assetPath.startsWith('img_sign/')) {
        assetPath = 'images/$assetPath';
      }
      return Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image_not_supported,
                    size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  AppStrings.get('image_load_failed'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  /// 構建吸底提交按鈕
  Widget _buildSubmitButton(String buttonText) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _allQuestionsAnswered ? _finishTest : null,
          borderRadius: BorderRadius.circular(32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: _allQuestionsAnswered
                  ? const Color(0xFF3B82F6) // 藍色背景
                  : Colors.grey[300], // 禁用狀態：灰色
              borderRadius: BorderRadius.circular(32),
              boxShadow: _allQuestionsAnswered
                  ? [
                      BoxShadow(
                        color: const Color(0xFF3B82F6).withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.send,
                  color:
                      _allQuestionsAnswered ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  buttonText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color:
                        _allQuestionsAnswered ? Colors.white : Colors.grey[600],
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
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

    // 獲取當前語言，用於顯示交卷按鈕文字
    final currentLang = _currentLanguage;
    final submitButtonText =
        currentLang == 'it' ? 'CONSEGNA' : AppStrings.get('submit_exam');

    return Scaffold(
      // 自定義 AppBar（毛玻璃效果）
      appBar: _buildGlassAppBar(context),
      body: Container(
        decoration: AppTheme.pageDecoration,
        child: Stack(
          children: [
            // 題目列表（滾動）
            ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), // 底部留出空間給提交按鈕
              itemCount: _questions.length,
              itemBuilder: (context, index) {
                return _buildQuestionCard(index);
              },
            ),
            // 吸底提交按鈕
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: _buildSubmitButton(submitButtonText),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
