import 'package:flutter/material.dart';
import 'dart:math' as math;
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
      // 內容比屏幕短時，透明底會在下方露出黑色窗口底，改用頁面底色。
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // 毛玻璃 AppBar
      appBar: _buildGlassAppBar(context),
      body: Container(
        decoration: AppTheme.pageDecorationFor(context),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 主卡片：狀態圖標和文字
                _isRoad ? _buildRoadResultCard() : _buildResultCard(),

                if (_isRoad) ..._buildRoadStickers(),

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

  bool get _isRoad => AppTheme.usesRoadPalette && !AppTheme.isRetroFor(context);

  /// 道路主題結果卡：通過時給一張「模擬駕照」，未通過時語氣溫和並指向錯題。
  Widget _buildRoadResultCard() {
    final isPassed = widget.isPassed;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor =
        isPassed ? AppTheme.successFor(context) : AppTheme.dangerFor(context);
    final ink = AppTheme.inkFor(context);
    final muted = AppTheme.mutedFor(context);
    final now = DateTime.now();
    final dateText = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final headline = Column(
      children: [
        // 窄屏（360dp）上 NON IDONEO 也保持一行，必要時等比縮小。
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            isPassed ? AppStrings.get('idoneo') : AppStrings.get('non_idoneo'),
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: statusColor,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isPassed
              ? AppStrings.get('congratulations')
              : AppStrings.get('mock_result_fail_gentle')
                  .replaceAll('{count}', '${widget.errors}'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
            height: 1.4,
          ),
        ),
      ],
    );

    if (!isPassed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        decoration: BoxDecoration(
          color: AppTheme.surfaceFor(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.lineFor(context), width: 1.5),
          boxShadow: AppTheme.cardShadowFor(context),
        ),
        child: Column(
          children: [
            _buildStatusIcon(isPassed, statusColor),
            const SizedBox(height: 16),
            headline,
          ],
        ),
      );
    }

    // 模擬駕照：意大利駕照的粉色卡面，略微傾斜，像剛拿到手。
    const licensePink = Color(0xFFF4D7DC);
    const licenseInk = Color(0xFF2A1E21);
    const licenseMuted = Color(0xFF5C474C);
    Widget code(String text) => Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: licenseMuted,
          ),
        );
    Widget field(Widget lead, String value, {double size = 14}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(width: 34, child: lead),
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w800,
                  color: licenseInk,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        headline,
        const SizedBox(height: 24),
        Transform.rotate(
          angle: -2 * math.pi / 180,
          child: Container(
            key: const Key('mock_result_license_card'),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: licensePink,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: licenseInk, width: 2),
              boxShadow: AppTheme.chunkyShadowFor(
                context,
                color: isDark ? Colors.black : AppTheme.roadPrimaryDark,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'PATENTE DI GUIDA',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: licenseInk,
                        ),
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1F4E9E),
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        'I',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.roadAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  AppStrings.get('mock_license_subtitle'),
                  style: const TextStyle(fontSize: 12, color: licenseMuted),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72,
                      height: 88,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8BCC4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 44,
                        color: licenseMuted,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          field(code('4a.'), dateText),
                          field(code('9.'), 'B', size: 18),
                          field(
                            const Icon(Icons.check_rounded,
                                size: 16, color: licenseMuted),
                            '${widget.correctAnswers} / ${widget.totalQuestions}',
                            size: 22,
                          ),
                          field(
                            const Icon(Icons.timer_outlined,
                                size: 16, color: licenseMuted),
                            _formatTime(_timeUsed),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${AppStrings.get('error_count')}: ${widget.errors}',
          style: TextStyle(fontSize: 14, color: muted),
        ),
      ],
    );
  }

  /// 本次成績換來的貼紙：只由本場結果推得，不寫入任何資料。
  List<Widget> _buildRoadStickers() {
    final stickers = <({IconData icon, String key, Color color})>[
      if (widget.isPassed)
        (
          icon: Icons.verified_rounded,
          key: 'sticker_passed',
          color: AppTheme.successFor(context),
        ),
      if (widget.errors == 0)
        (
          icon: Icons.workspace_premium_rounded,
          key: 'sticker_perfect',
          color: AppTheme.warningTextFor(context),
        ),
      if (widget.isPassed && _timeUsed <= MockTestConfig.timeLimitSeconds ~/ 2)
        (
          icon: Icons.bolt_rounded,
          key: 'sticker_fast',
          color: AppTheme.warningTextFor(context),
        ),
    ];
    if (stickers.isEmpty) return const [];
    final ink = AppTheme.inkFor(context);
    return [
      const SizedBox(height: 24),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          AppStrings.get('stickers_earned_title'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        key: const Key('mock_result_stickers'),
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var i = 0; i < stickers.length; i++)
            Transform.rotate(
              angle: (i.isEven ? -2 : 2) * math.pi / 180,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceFor(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ink, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(stickers[i].icon, size: 22, color: stickers[i].color),
                    const SizedBox(width: 6),
                    Text(
                      AppStrings.get(stickers[i].key),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ];
  }

  /// 構建毛玻璃 AppBar
  PreferredSizeWidget _buildGlassAppBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    // 道路主題：標題欄與頁面同為實色底，不再使用灰色毛玻璃。
    final isRoad = _isRoad;
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: isRetro || isRoad ? 0 : 20,
            sigmaY: isRetro || isRoad ? 0 : 20,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isRoad
                  ? AppTheme.pageDecorationFor(context).color
                  : colorScheme.surface.withOpacity(0.82),
              border: isRoad
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: colorScheme.outline.withOpacity(0.2),
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
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      color: colorScheme.onSurfaceVariant,
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    // 中間：標題
                    Expanded(
                      child: Center(
                        child: Text(
                          AppStrings.get('test_result'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: isRoad ? FontWeight.w800 : FontWeight.w600,
                            color: isRoad
                                ? AppTheme.inkFor(context)
                                : colorScheme.onSurface,
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
    final isRetro = AppTheme.isRetroFor(context);
    final iconWidget = Stack(
      alignment: Alignment.center,
      children: [
        // 外圈裝飾
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: isRetro ? BoxShape.rectangle : BoxShape.circle,
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
            shape: isRetro ? BoxShape.rectangle : BoxShape.circle,
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
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final isPassed = widget.isPassed;
    final statusColor =
        isPassed ? AppTheme.successFor(context) : AppTheme.dangerFor(context);
    final cardRadius = isRetro ? BorderRadius.zero : BorderRadius.circular(32);

    return ClipRRect(
      borderRadius: cardRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: isRetro ? 0 : 20,
          sigmaY: isRetro ? 0 : 20,
        ),
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: colorScheme.surface.withOpacity(0.9),
            borderRadius: cardRadius,
            border: Border.all(color: AppTheme.lineFor(context)),
            boxShadow: AppTheme.cardShadowFor(context),
          ),
          child: Column(
            children: [
              // 狀態圖標（綠色勾號或紅色叉號）
              _buildStatusIcon(isPassed, statusColor),
              const SizedBox(height: 16),
              // 大標題（合格/不合格 或 IDONEO/NON IDONEO）
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  isPassed
                      ? AppStrings.get('idoneo')
                      : AppStrings.get('non_idoneo'),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 錯誤數
              Text(
                '${AppStrings.get('error_count')}: ${widget.errors}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
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
                    borderRadius: isRetro
                        ? BorderRadius.zero
                        : BorderRadius.circular(999),
                    border:
                        isRetro ? Border.all(color: AppTheme.retroLine) : null,
                  ),
                  child: Text(
                    AppStrings.get('congratulations'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                      letterSpacing: 0,
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
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final cardRadius = isRetro ? BorderRadius.zero : BorderRadius.circular(32);
    return ClipRRect(
      borderRadius: cardRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: isRetro ? 0 : 20,
          sigmaY: isRetro ? 0 : 20,
        ),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colorScheme.surface.withOpacity(0.9),
            borderRadius: cardRadius,
            border: Border.all(color: AppTheme.lineFor(context)),
            boxShadow: AppTheme.cardShadowFor(context),
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
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    // 評價跟隨考試結果：通過用主色，未通過用警示色，不再一律綠色。
    final primaryValueColor = widget.isPassed
        ? colorScheme.primary
        : AppTheme.dangerFor(context);
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: isPrimary ? primaryValueColor : colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isRetro ? 12 : 11,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isPrimary ? 18 : 20,
            fontWeight: FontWeight.bold,
            color: isPrimary ? primaryValueColor : colorScheme.onSurface,
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
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final primaryColor = AppTheme.primaryFor(context);
    final buttonRadius =
        isRetro ? BorderRadius.zero : BorderRadius.circular(20);
    if (_isRoad) {
      final background =
          isPrimary ? AppTheme.accentFor(context) : AppTheme.surfaceFor(context);
      final foreground =
          isPrimary ? AppTheme.onAccentFor(context) : AppTheme.inkFor(context);
      final radius = BorderRadius.circular(14);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: AppTheme.chunkyShadowFor(
            context,
            color: isPrimary ? null : AppTheme.lineFor(context),
          ),
        ),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: isPrimary ? AppTheme.roadInk : AppTheme.lineFor(context),
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: foreground,
                        ),
                        maxLines: 1,
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
    return ClipRRect(
      borderRadius: buttonRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: isRetro ? 0 : 20,
          sigmaY: isRetro ? 0 : 20,
        ),
        child: Material(
          color:
              isPrimary ? primaryColor : colorScheme.surface.withOpacity(0.82),
          child: InkWell(
            onTap: onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: buttonRadius,
                border: isPrimary
                    ? null
                    : Border.all(
                        color: colorScheme.outlineVariant,
                        width: 1,
                      ),
                boxShadow: isRetro
                    ? const []
                    : [
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
                    color: isPrimary
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
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
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
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
