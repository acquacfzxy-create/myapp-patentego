import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../providers/user_state_provider.dart';
import '../services/database_service.dart';
import '../widgets/question_widget.dart';
import '../widgets/translation_panel.dart';
import 'subscription_page.dart';

/// 考後復盤頁面
/// 顯示本次模擬考試的所有題目，包括用戶答案和正確答案
class ExamReviewScreen extends StatefulWidget {
  /// 本次考試的所有題目（30道）
  final List<Question> questions;

  /// 用戶的答案記錄（索引 -> 答案，null表示未作答）
  final Map<int, bool?> userChoices;

  const ExamReviewScreen({
    super.key,
    required this.questions,
    required this.userChoices,
  });

  @override
  State<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ExamReviewScreenState extends State<ExamReviewScreen> {
  // 記錄每道題的展開狀態（僅翻譯；解析改為底部彈窗，與練習模式一致）
  final Map<int, bool> _showTranslation = {};

  // 當前語言（從 Provider 獲取）
  String get _currentLanguage =>
      Provider.of<UserStateProvider>(context, listen: false).currentLanguage;

  /// 切換翻譯顯示
  void _toggleTranslation(int index) {
    setState(() {
      _showTranslation[index] = !(_showTranslation[index] ?? false);
    });
  }

  /// 打開與練習模式一致的解析底部彈窗（限額檢查與計次與練習模式一致）
  Future<void> _openExplanationSheet(int index) async {
    final question = widget.questions[index];
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    final questionId = question.id;
    final isVip = userStateProvider.isVip;

    if (!userStateProvider.canViewExplanation(questionId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.get('explanation_limit_reached_message')),
          duration: const Duration(seconds: 2),
        ),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SubscriptionPage(),
        ),
      );
      return;
    }

    final alreadyUnlockedToday =
        userStateProvider.isExplanationUnlockedToday(questionId);
    final remainingBefore = userStateProvider.remainingExplanations;

    await QuestionWidget.showRichExplanation(
      context,
      question: question,
      currentLanguage: _currentLanguage,
      remainingExplanations:
          (!isVip && !alreadyUnlockedToday) ? remainingBefore : null,
      showVipBadgeOnStudyTip: !isVip,
    );

    if (!isVip && !alreadyUnlockedToday) {
      await userStateProvider.incrementExplanationCount(questionId);
    }
  }

  /// 切換收藏狀態
  Future<void> _toggleFavorite(int index) async {
    final question = widget.questions[index];
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);

    await DatabaseService.toggleFavorite(
      question.id,
      userId: userStateProvider.effectiveUserId,
    );

    setState(() {}); // 刷新UI
  }

  /// 檢查是否收藏
  Future<bool> _isFavorite(int index) async {
    final question = widget.questions[index];
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    return await DatabaseService.isFavorite(
      question.id,
      userId: userStateProvider.effectiveUserId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 毛玻璃 AppBar
      appBar: _buildGlassAppBar(context),
      body: Container(
        decoration: AppTheme.pageDecoration,
        child: Consumer<UserStateProvider>(
          builder: (context, userStateProvider, _) {
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.questions.length,
              itemBuilder: (context, index) {
                final userChoice = widget.userChoices[index];
                final isIncorrectOrUnanswered =
                    userChoice != widget.questions[index].answer;
                final isLocked = userStateProvider.shouldLockReview(index) &&
                    !isIncorrectOrUnanswered;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: isLocked
                      ? _buildLockedReviewCard(index)
                      : _buildQuestionCard(index),
                );
              },
            );
          },
        ),
      ),
    );
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
                    // 左側：返回按鈕（純圖標）
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      color: const Color(0xFF475569),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    // 中間：標題
                    Expanded(
                      child: Center(
                        child: Text(
                          AppStrings.get('view_test_errors'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ),
                    // 右側：占位
                    const SizedBox(width: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 構建鎖定的題目卡片（非 VIP：第 11 題起僅鎖正確題；錯題/未答題仍可復盤）
  Widget _buildLockedReviewCard(int index) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const SubscriptionPage(),
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildQuestionCard(index),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  color: Colors.white.withOpacity(0.5),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.lock,
                    size: 48,
                    color: Color(0xFFD4AF37),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 構建題目卡片
  Widget _buildQuestionCard(int index) {
    final question = widget.questions[index];
    final userChoice = widget.userChoices[index];
    final correctAnswer = question.answer;
    final questionText = question.getDisplayQuestionText(
      defaultText: AppStrings.get('question_content_missing'),
    );
    final translationText = question.getQuestionText(_currentLanguage);
    final hasImage =
        question.imageName != null && question.imageName!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左欄 (Gutter)：題號徽章 + V/F 圓圈
                _buildLeftGutter(index, correctAnswer, userChoice),
                const SizedBox(width: 12),

                // 中欄 (Content)：題目內容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: hasImage
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center, // 無圖片時垂直居中
                    children: [
                      // 意語題目文本（最高優先級，字號和對比度最高）
                      Text(
                        questionText,
                        style: const TextStyle(
                          fontSize: 17, // 略微增大，強化信息層級
                          fontWeight: FontWeight.w600, // 增加字重，提高對比度
                          height: 1.5,
                          color: Color(0xFF0D131B), // 更深的黑色，提高對比度
                        ),
                      ),

                      // 圖片（如果有）
                      if (hasImage) ...[
                        const SizedBox(height: 16),
                        _buildQuestionImage(question.imageName!),
                      ],

                      // 翻譯內容（如果展開）
                      if (_showTranslation[index] == true &&
                          translationText != null) ...[
                        const SizedBox(height: 16),
                        TranslationPanel(
                          text: translationText,
                          languageCode: _currentLanguage,
                        ),
                      ],

                      // 關鍵詞（如果展開翻譯）
                      if (_showTranslation[index] == true) ...[
                        const SizedBox(height: 12),
                        _buildKeyWordsChips(index),
                      ],

                      const SizedBox(height: 16),
                      _buildBottomActions(index),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 構建左欄（題號徽章 + V/F 圓圈）
  Widget _buildLeftGutter(int index, bool correctAnswer, bool? userChoice) {
    // 強制應用"閱卷紅線"邏輯：
    // - 綠色圓圈：正確答案始終顯示綠色
    // - 紅色斜線：只有當用戶選錯了（userChoice != null && userChoice != correctAnswer）時才顯示

    // 判定：用戶是否選錯了 V（用戶選了 V 但正確答案是 F）
    final isVWrong =
        userChoice != null && userChoice == true && correctAnswer == false;

    // 判定：用戶是否選錯了 F（用戶選了 F 但正確答案是 V）
    final isFWrong =
        userChoice != null && userChoice == false && correctAnswer == true;

    // 增強調試信息：打印每個圓圈的判定結果
    if (kDebugMode) {}

    // 增強調試信息：打印每個圓圈的判定結果
    if (kDebugMode) {}

    return SizedBox(
      width: 44,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 題號徽章（極淺灰色，僅數字）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // V 圓圈
          _buildAnswerCircle(
            label: 'V',
            isCorrect: correctAnswer == true, // 正確答案是 V -> 顯示綠色
            isWrong: isVWrong, // 用戶錯誤地選了 V -> 顯示紅線
          ),
          const SizedBox(height: 12),

          // F 圓圈
          _buildAnswerCircle(
            label: 'F',
            isCorrect: correctAnswer == false, // 正確答案是 F -> 顯示綠色
            isWrong: isFWrong, // 用戶錯誤地選了 F -> 顯示紅線
          ),
        ],
      ),
    );
  }

  /// 構建答案圓圈（V 或 F）
  ///
  /// 邏輯說明（強制應用"閱卷紅線"邏輯）：
  /// - 綠色圓圈（正確路標）：
  ///   - 如果 `isCorrect == true` -> 顯示綠色（帶圓圈背景或邊框）
  /// - 紅色斜線（選錯劃掉）：
  ///   - 只有當 `isWrong == true` 時才觸發
  ///   - 在用戶選錯的那個字母上覆蓋紅色斜杠
  Widget _buildAnswerCircle({
    required String label,
    required bool isCorrect, // 是否為正確答案
    required bool isWrong, // 用戶是否選錯了這個選項
  }) {
    // 調試：檢查 isWrong 參數
    if (kDebugMode && isWrong) {}

    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 圓圈背景
          // 核心邏輯：正確答案始終顯示綠色，無論用戶選了什麼
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCorrect
                  ? const Color(0xFF22C55E)
                      .withOpacity(0.15) // 正確答案：淡綠色背景（始終顯示）
                  : Colors.transparent,
              border: Border.all(
                color: isCorrect
                    ? const Color(0xFF22C55E) // 正確答案：綠色邊框（始終顯示）
                    : Colors.grey[300]!,
                width: isCorrect ? 2 : 1.5,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [
                    FontFeature.tabularFigures()
                  ], // Monospace 效果
                  color: isCorrect
                      ? const Color(0xFF22C55E) // 正確答案：綠色文字（始終顯示）
                      : Colors.grey[500], // 未選中：灰色文字
                ),
              ),
            ),
          ),

          // 用戶選錯標記（紅色斜線，模擬老師用紅筆劃掉）
          // 只有當用戶選錯了（isWrong = true）時，才在用戶選的那個錯誤字母上畫紅線
          // 紅杠在 Stack 的最頂層，確保覆蓋在圓圈上方
          if (isWrong)
            Positioned.fill(
              child: CustomPaint(
                painter: _RedSlashPainter(),
              ),
            ),
        ],
      ),
    );
  }

  /// 構建底部功能按鈕，避免窄屏時右側欄擠壓題目與關鍵詞寬度
  Widget _buildBottomActions(int index) {
    return FutureBuilder<bool>(
      future: _isFavorite(index),
      builder: (context, snapshot) {
        final isFavorite = snapshot.data ?? false;

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                size: 22,
                color: isFavorite ? Colors.red : Colors.grey[600],
              ),
              onPressed: () => _toggleFavorite(index),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: Icon(Icons.menu_book_outlined,
                  size: 22, color: Colors.grey[600]),
              onPressed: () async {
                await _openExplanationSheet(index);
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: Icon(
                Icons.translate,
                size: 22,
                color: _showTranslation[index] == true
                    ? const Color(0xFF137FEC)
                    : Colors.grey[600],
              ),
              onPressed: () => _toggleTranslation(index),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        );
      },
    );
  }

  /// 構建題目圖片
  Widget _buildQuestionImage(String imagePath) {
    // 處理圖片路徑
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imagePath,
          height: 120,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.shrink(); // 錯誤時完全移除
          },
        ),
      );
    } else {
      String assetPath = imagePath;
      if (assetPath.startsWith('/')) {
        assetPath = assetPath.substring(1);
      }
      if (assetPath.startsWith('img_sign/')) {
        assetPath = 'images/$assetPath';
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          assetPath,
          height: 120,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.shrink(); // 錯誤時完全移除
          },
        ),
      );
    }
  }

  /// 構建關鍵詞標籤
  Widget _buildKeyWordsChips(int index) {
    final question = widget.questions[index];
    final keywords = question.getKeyWords(_currentLanguage);

    if (keywords.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: keywords.map((keyword) {
            final itWord = keyword['it'] ?? '';
            final translation = keyword[_currentLanguage] ??
                keyword['en'] ??
                keyword['zh'] ??
                '';

            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      itWord,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      '•',
                      style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                    ),
                    Text(
                      translation,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// 紅色斜線繪製器（模擬老師用紅筆劃掉的效果）
///
/// 視覺精修：
/// - 顏色：鮮豔的紅色 (Colors.red)
/// - 厚度：2px
/// - 角度：-45度（從左上到右下）
/// - 寬度：稍微超出圓圈一點，模仿老師批改的效果
class _RedSlashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red // 鮮豔的紅色
      ..strokeWidth = 2.0 // 厚度 2px
      ..strokeCap = StrokeCap.round; // 圓角端點，更像手寫效果

    // 從左上到右下畫一條斜線（-45度）
    // 稍微超出圓圈，模擬手寫效果
    const startX = -6.0;
    const startY = -6.0;
    final endX = size.width + 6.0;
    final endY = size.height + 6.0;

    canvas.drawLine(
      Offset(startX, startY),
      Offset(endX, endY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
