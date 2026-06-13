import 'package:flutter/material.dart';
import 'dart:ui';
import '../config/mock_test_config.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../models/question.dart';
import 'exam_review_screen.dart';
import 'mock_test_screen.dart';
import 'home_screen.dart';

/// 模擬考試結果頁面
class MockTestResultScreen extends StatefulWidget {
  final int totalQuestions;
  final int correctAnswers;
  final int errors;
  final bool isPassed;
  final int timeRemaining;
  final List<String> errorIds;
  final List<Question> questions; // 本次考試的所有題目
  final Map<int, bool?> userChoices; // 用戶的答案記錄

  const MockTestResultScreen({
    super.key,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.errors,
    required this.isPassed,
    required this.timeRemaining,
    required this.errorIds,
    required this.questions,
    required this.userChoices,
  });

  @override
  State<MockTestResultScreen> createState() => _MockTestResultScreenState();
}

class _MockTestResultScreenState extends State<MockTestResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController? _animationController;
  late Animation<double>? _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // 僅在不及格時初始化動畫
    if (!widget.isPassed) {
      _animationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      )..repeat(reverse: true);

      _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(
          parent: _animationController!,
          curve: Curves.easeInOut,
        ),
      );
    } else {
      _animationController = null;
      _pulseAnimation = null;
    }
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  /// 計算實際用時（總時間 - 剩餘時間）
  int get _timeUsed => MockTestConfig.timeLimitSeconds - widget.timeRemaining;

  /// 計算正確率（百分比）
  double get _accuracyRate =>
      ((widget.totalQuestions - widget.errors) / widget.totalQuestions * 100);

  /// 根據錯誤數獲取評價（使用 AppStrings 確保多語言）
  String _getRating() {
    if (widget.errors == 0) {
      return AppStrings.get('eccellente'); // 完美
    } else if (widget.errors <= 2) {
      return AppStrings.get('ottimo'); // 优秀
    } else if (widget.errors == 3) {
      return AppStrings.get('buono'); // 良好
    } else {
      return AppStrings.get('keep_trying'); // 仍需加油（错误数 > 3）
    }
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// 查看本套試卷的錯題（跳轉到考後復盤頁）
  void _viewTestErrors() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExamReviewScreen(
          questions: widget.questions,
          userChoices: widget.userChoices,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 毛玻璃 AppBar
      appBar: _buildGlassAppBar(context),
      body: Container(
        decoration: AppTheme.pageDecoration,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 主卡片：狀態圖標和文字
                _buildResultCard(),

                const SizedBox(height: 24),

                // 數據統計行
                _buildStatsRow(),

                const SizedBox(height: 32),

                // 操作按鈕
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildActionButtons(),
                ),
              ],
            ),
          ),
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
                    // 左側：返回按鈕（純圖標，與練習模式一致）
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
                          AppStrings.get('test_result'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ),
                    // 右側：占位
                    const SizedBox(width: 80),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 構建狀態圖標（帶動畫效果）
  Widget _buildStatusIcon(bool isPassed, Color statusColor) {
    final iconWidget = Stack(
      alignment: Alignment.center,
      children: [
        // 外圈裝飾
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: statusColor.withOpacity(0.2),
              width: 2,
            ),
          ),
        ),
        // 內圈背景
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: statusColor.withOpacity(0.1),
          ),
          child: Icon(
            isPassed ? Icons.check_circle : Icons.cancel,
            size: 60,
            color: statusColor,
          ),
        ),
      ],
    );

    // 不及格時添加呼吸燈動畫
    if (!isPassed && _pulseAnimation != null) {
      return AnimatedBuilder(
        animation: _pulseAnimation!,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation!.value,
            child: iconWidget,
          );
        },
      );
    }

    return iconWidget;
  }

  /// 構建主卡片：狀態圖標和文字
  Widget _buildResultCard() {
    final isPassed = widget.isPassed;
    final statusColor =
        isPassed ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF137FEC).withOpacity(0.05),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // 狀態圖標（綠色勾號或紅色叉號）
              _buildStatusIcon(isPassed, statusColor),
              const SizedBox(height: 16),
              // 大標題（合格/不合格 或 IDONEO/NON IDONEO）
              Text(
                isPassed
                    ? AppStrings.get('idoneo')
                    : AppStrings.get('non_idoneo'),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              // 錯誤數
              Text(
                '${AppStrings.get('error_count')}: ${widget.errors}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              // 獎勵標籤（僅及格時顯示）
              if (isPassed) ...[
                const SizedBox(height: 24),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    AppStrings.get('congratulations'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 構建數據統計行（三個立柱式統計項）
  Widget _buildStatsRow() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF137FEC).withOpacity(0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final halfWidth = (constraints.maxWidth - 16) / 2;
              return Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: halfWidth,
                    child: _buildStatItem(
                      icon: Icons.timer,
                      label: AppStrings.get('time_used'),
                      value: _formatTime(_timeUsed),
                      isPrimary: false,
                    ),
                  ),
                  SizedBox(
                    width: halfWidth,
                    child: _buildStatItem(
                      icon: Icons.analytics,
                      label: AppStrings.get('accuracy_rate'),
                      value: '${_accuracyRate.toStringAsFixed(0)}%',
                      isPrimary: false,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: _buildStatItem(
                      icon: Icons.stars,
                      label: AppStrings.get('rating'),
                      value: _getRating(),
                      isPrimary: true,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 構建單個統計項
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required bool isPrimary,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: isPrimary ? const Color(0xFF137FEC) : Colors.grey[400],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey[400],
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isPrimary ? 18 : 20,
            fontWeight: FontWeight.bold,
            color:
                isPrimary ? const Color(0xFF137FEC) : const Color(0xFF1E293B),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// 構建操作按鈕
  Widget _buildActionButtons() {
    return Row(
      children: [
        // 查看錯題按鈕（黑色背景，僅在有錯題時顯示）
        if (widget.errorIds.isNotEmpty)
          Expanded(
            child: _buildActionButton(
              onPressed: _viewTestErrors,
              icon: Icons.error_outline,
              label: AppStrings.get('view_test_errors'),
              isPrimary: true,
            ),
          ),
        if (widget.errorIds.isNotEmpty) const SizedBox(width: 16),
        // 再考一次按鈕（白色背景帶邊框）
        Expanded(
          child: _buildActionButton(
            onPressed: () {
              final navigator = Navigator.of(context);
              // 先清除所有頁面並回到主頁，然後再進入新的考試界面
              // 這樣確保返回按鈕能正常返回到主頁
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => const HomeScreen(),
                ),
                (route) => false, // 清除所有之前的頁面
              );
              // 使用 Future.microtask 確保主頁已經在導航棧中後再跳轉
              Future.microtask(() {
                navigator.push(
                  MaterialPageRoute(
                    builder: (context) => const MockTestScreen(),
                  ),
                );
              });
            },
            icon: Icons.refresh,
            label: AppStrings.get('restart'),
            isPrimary: false,
          ),
        ),
      ],
    );
  }

  /// 構建單個操作按鈕
  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required bool isPrimary,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: isPrimary
              ? const Color(0xFF1E293B) // 黑色背景
              : Colors.white.withOpacity(0.7), // 白色背景
          child: InkWell(
            onTap: onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: isPrimary
                    ? null
                    : Border.all(
                        color: Colors.grey[300]!,
                        width: 1,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isPrimary ? Colors.white : const Color(0xFF1E293B),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isPrimary
                              ? Colors.white
                              : const Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
