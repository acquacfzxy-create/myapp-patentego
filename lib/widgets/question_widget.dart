import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import 'dart:math' show max;
import 'dart:ui';
import '../models/question.dart';
import '../services/database_service.dart';
import '../services/explanation_parser.dart';
import '../services/question_speech_service.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../providers/user_state_provider.dart';
import '../screens/voice_pack_screen.dart';
import 'glass_card.dart';
import 'answer_motion.dart';
import 'bouncy_press.dart';
import 'explanation_emphasis.dart';
import 'streak_jitter.dart';
import 'translation_panel.dart';

/// 題目顯示組件
/// 負責顯示題目內容、圖片、選項和解析
class QuestionWidget extends StatefulWidget {
  final Question question;
  final Function(bool) onAnswerSelected;
  /// Lets the practice page suspend auto-advance while reading support is open.
  final ValueChanged<bool>? onReadingChanged;
  final String currentLanguage;
  final int? currentIndex;
  final int? totalQuestions;
  final bool isExamMode; // 是否為考試模式
  final bool? selectedAnswer; // 用戶之前選擇的答案（null表示未選擇）
  final bool hasPreviousQuestion; // 是否有上一題
  final bool hasNextQuestion; // 是否有下一題
  final VoidCallback? onPreviousQuestion; // 上一題回調
  final VoidCallback? onNextQuestion; // 下一題回調
  final bool showQuestionCounter; // 是否顯示題目計數器（隨機刷題模式隱藏，章節練習和模擬考試顯示）

  // 答题状态（由 PracticeScreen 管理，仅用于 UI 反馈）
  final bool isAnswered; // 是否已点击答案
  final bool? isCorrect; // 答案是否正确
  final bool? userChoice; // 用户选的是 Vero 还是 Falso
  final bool showFavoriteBadge; // 是否显示收藏气泡
  final bool showMasteredBadge; // 是否显示精通气泡
  final bool hideCorrectBadge; // 是否隐藏"正确"气泡（当显示精通气泡时）
  final bool mistakeEliminated; // 错题是否已彻底消灭（wrong_count 降到 0）
  final int sessionCorrectStreak; // 本次練習連續答對題數
  final int questionMasteryStep; // 單題掌握進度（0-3）

  const QuestionWidget({
    super.key,
    required this.question,
    required this.onAnswerSelected,
    this.onReadingChanged,
    required this.currentLanguage,
    this.currentIndex,
    this.totalQuestions,
    this.isExamMode = false, // 默認為練習模式
    this.selectedAnswer,
    this.hasPreviousQuestion = false,
    this.hasNextQuestion = false,
    this.onPreviousQuestion,
    this.onNextQuestion,
    this.showQuestionCounter = true, // 默認顯示（向後兼容）
    this.isAnswered = false,
    this.isCorrect,
    this.userChoice,
    this.showFavoriteBadge = false,
    this.showMasteredBadge = false,
    this.hideCorrectBadge = false,
    this.mistakeEliminated = false,
    this.sessionCorrectStreak = 0,
    this.questionMasteryStep = 0,
  });

  /// 全 App 統一的解析底部彈窗（練習、考後復盤等共用，自動識別 JSON / 純文本）
  /// Legacy quota arguments are ignored: full explanations are free and unlimited.

  static Future<void> showRichExplanation(
    BuildContext context, {
    required Question question,
    required String currentLanguage,
    int? remainingExplanations,
    bool showVipBadgeOnStudyTip = false,
  }) async {
    final correctAnswer = question.answer ? 'Vero' : 'Falso';
    final explanationText = question.getExplanationText(currentLanguage) ??
        question.getExplanationText('it') ??
        AppStrings.getWithLanguage(
            currentLanguage, 'explanation_missing_short');

    final parsedExplanation = ExplanationParser.parse(explanationText);
    final detailedDescription = parsedExplanation.detailedDescription;
    final isRetro = AppTheme.isRetroFor(context);
    final primaryColor = AppTheme.primaryFor(context);
    final inkColor = AppTheme.inkFor(context);
    final mutedColor = AppTheme.mutedFor(context);
    final colorScheme = Theme.of(context).colorScheme;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        return ClipRRect(
          borderRadius: isRetro
              ? BorderRadius.zero
              : const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.radiusXl),
                  topRight: Radius.circular(AppTheme.radiusXl),
                ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(bottomSheetContext).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: AppTheme.surfaceFor(context),
              border: isRetro ? Border.all(color: AppTheme.retroLine) : null,
              borderRadius: isRetro
                  ? BorderRadius.zero
                  : const BorderRadius.only(
                      topLeft: Radius.circular(AppTheme.radiusXl),
                      topRight: Radius.circular(AppTheme.radiusXl),
                    ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.lineFor(context).withOpacity(0.7),
                      borderRadius: isRetro
                          ? BorderRadius.zero
                          : BorderRadius.circular(2),
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      8,
                      24,
                      MediaQuery.viewPaddingOf(bottomSheetContext).bottom + 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySoftFor(context),
                            borderRadius: isRetro
                                ? BorderRadius.zero
                                : BorderRadius.circular(12),
                            border: Border.all(
                              color: primaryColor.withOpacity(0.22),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 标签可换行，避免长语言或放大字号时与答案徽章重叠溢出。
                              Expanded(
                                child: Text(
                                  AppStrings.getWithLanguage(currentLanguage,
                                      'modal_correct_answer_label'),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: inkColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  borderRadius: isRetro
                                      ? BorderRadius.zero
                                      : BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Text(
                                    correctAnswer,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isRetro
                                          ? AppTheme.retroPage
                                          : colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          AppStrings.getWithLanguage(
                              currentLanguage, 'detail_description_title'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: mutedColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
                          ExplanationEmphasis.build(
                            context,
                            detailedDescription,
                            base: TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              color: inkColor,
                            ),
                          ),
                        ),
                        buildExplanationSupplement(
                          context,
                          parsedExplanation: parsedExplanation,
                          currentLanguage: currentLanguage,
                          showVipBadgeOnStudyTip: false,

                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 內部工具：將文本中括號內內容用較淡顏色顯示，括號外保持主色
  static TextSpan buildTextWithSoftParenthesis(
    String text,
    TextStyle baseStyle,
    TextStyle parenthesisStyle,
  ) {
    final spans = <TextSpan>[];
    final regExp = RegExp(r'\([^()]*\)');
    int currentIndex = 0;

    for (final match in regExp.allMatches(text)) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, match.start),
          style: baseStyle,
        ));
      }
      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: parenthesisStyle,
      ));
      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: baseStyle,
      ));
    }

    return TextSpan(children: spans, style: baseStyle);
  }

  /// 教練小貼士：與詳細說明、考點使用同一套重點標記規則（見 ExplanationEmphasis）。
  static TextSpan buildStudyTipMarkdownSpan(String text, BuildContext context) {
    return ExplanationEmphasis.build(
      context,
      text,
      base: TextStyle(
        fontSize: 14,
        height: 1.6,
        color: AppTheme.primaryFor(context),
      ),
    );
  }

  /// Shared supplementary content: deliberately excludes the description.
  static Widget buildExplanationSupplement(
    BuildContext context, {
    required ParsedExplanation parsedExplanation,
    required String currentLanguage,
    bool showVipBadgeOnStudyTip = false,
    VoidCallback? onStudyTipTap,
  }) {
    final keyPoints = parsedExplanation.keyPoints;
    final studyTip = parsedExplanation.studyTip;
    final isJsonFormat = parsedExplanation.isJsonFormat;
    final primaryColor = AppTheme.primaryFor(context);
    final mutedColor = AppTheme.mutedFor(context);
    final inkColor = AppTheme.inkFor(context);
    final isRetro = AppTheme.isRetroFor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
      if (isJsonFormat &&
          keyPoints != null &&
          keyPoints.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text(
          AppStrings.getWithLanguage(
              currentLanguage, 'key_points_title'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: mutedColor,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        ...(keyPoints.map((point) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(
                      top: 6, right: 10),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    shape: isRetro
                        ? BoxShape.rectangle
                        : BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: inkColor,
                      ),
                      children: [
                        ExplanationEmphasis.build(
                          context,
                          '${point['title']}：',
                          base: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: inkColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        ExplanationEmphasis.build(
                          context,
                          point['content'] ?? '',
                          base: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: inkColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        })),
      ],
      if (isJsonFormat &&
          studyTip != null &&
          studyTip.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text(
          AppStrings.getWithLanguage(
              currentLanguage, 'study_tip_title'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: mutedColor,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        _StudyTipSection(
          showVipBadge: false,
          onTap: null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: AppTheme.warningFor(context),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  buildStudyTipMarkdownSpan(studyTip, context),
                  strutStyle: const StrutStyle(
                    fontSize: 14,
                    height: 1.6,
                    leadingDistribution:
                        TextLeadingDistribution.even,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      ],
    );
  }

  @override
  State<QuestionWidget> createState() => _QuestionWidgetState();
}

/// 解析彈窗內的「學習小貼士」區塊：可選顯示 ✨ VIP 標籤（呼吸燈動畫）與點擊跳轉訂閱頁
class _StudyTipSection extends StatefulWidget {
  final bool showVipBadge;
  final VoidCallback? onTap;
  final Widget child;

  const _StudyTipSection({
    required this.showVipBadge,
    required this.onTap,
    required this.child,
  });

  @override
  State<_StudyTipSection> createState() => _StudyTipSectionState();
}

class _StudyTipSectionState extends State<_StudyTipSection>
    with SingleTickerProviderStateMixin {
  AnimationController? _scaleController;
  Animation<double>? _scaleAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.showVipBadge) {
      _scaleController = AnimationController(
        duration: const Duration(milliseconds: 1600),
        vsync: this,
      )..repeat(reverse: true);
      _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(parent: _scaleController!, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void dispose() {
    _scaleController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRetro = AppTheme.isRetroFor(context);
    final primaryColor = AppTheme.primaryFor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vipColor = AppTheme.warningTextFor(context);
    final vipForeground = isRetro
        ? AppTheme.retroPage
        : isDark
            ? Colors.black
            : Colors.white;
    Widget content = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 48, 16),
          decoration: BoxDecoration(
            color: AppTheme.primarySoftFor(context),
            borderRadius:
                isRetro ? BorderRadius.zero : BorderRadius.circular(12),
            border: Border.all(
              color: primaryColor.withOpacity(0.22),
              width: 1,
            ),
          ),
          child: widget.child,
        ),
        if (widget.showVipBadge && _scaleAnimation != null)
          Positioned(
            top: 4,
            right: 4,
            child: ScaleTransition(
              scale: _scaleAnimation!,
              child: Container(
                // 最少 18 高：放大字号或较高字形时标签随文字长高，避免裁切。
                constraints: const BoxConstraints(minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isRetro ? AppTheme.retroPrimary : null,
                  gradient: isRetro
                      ? null
                      : LinearGradient(
                          colors: [vipColor, vipColor.withOpacity(0.82)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(4),
                ),
                child: Text(
                  '✨ VIP',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: vipForeground,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (widget.onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: isRetro ? BorderRadius.zero : BorderRadius.circular(12),
          child: content,
        ),
      );
    }

    return content;
  }
}

class _QuestionWidgetState extends State<QuestionWidget>
    with SingleTickerProviderStateMixin {
  /// 侧边操作按钮列距屏幕行尾的距离（与卡片行尾边缘对齐）。
  static const double _actionRailEndInset = 20;

  /// 按钮列的实际宽度（48dp 按钮加阴影与描边的外扩）。
  static const double _actionRailWidth = 52;

  /// 按钮列占用的行尾宽度（含与文字的间距），卡片内容在此之外排版。
  static const double _actionRailReserve =
      _actionRailEndInset + _actionRailWidth + 8;

  bool _showExplanation = false;
  bool _isFavorite = false;
  bool _showTranslation = false; // 翻譯顯示狀態
  bool _isExplanationOpen = false;

  void _notifyReadingChanged() {
    widget.onReadingChanged?.call(_showTranslation || _isExplanationOpen);
  }
  bool _isSpeakingQuestion = false;
  bool _isPreparingSpeech = false;
  int _speechSession = 0;
  final QuestionSpeechService _speechService = QuestionSpeechService();
  final ScrollController _scrollController = ScrollController(); // 用於自動滾動

  // 滑动卡片相关
  double _dragOffset = 0.0; // 当前拖拽偏移量
  AnimationController? _dragAnimationController;
  Animation<double>? _dragAnimation;

  @override
  void initState() {
    super.initState();
    _loadFavoriteStatus();
    // 初始化拖拽动画控制器
    _dragAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _dragAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _dragAnimationController!,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _speechSession++;
    _speechService.dispose();
    _scrollController.dispose();
    _dragAnimationController?.dispose();
    super.dispose();
  }

  /// 當題目更新時，重置翻譯和解析顯示狀態
  @override
  void didUpdateWidget(QuestionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果題目ID改變，重置翻譯和解析顯示狀態，并重置拖拽状态
    if (oldWidget.question.id != widget.question.id) {
      _speechSession++;
      _speechService.stop();
      setState(() {
        _showTranslation = false;
        _showExplanation = false;
        _isSpeakingQuestion = false;
        _isPreparingSpeech = false;
        _resetDragState();
      });
    }
  }

  /// 加載收藏狀態
  Future<void> _loadFavoriteStatus() async {
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    final isFav = await DatabaseService.isFavorite(
      widget.question.id,
      userId: userStateProvider.effectiveUserId,
    );
    if (mounted) {
      setState(() {
        _isFavorite = isFav;
      });
    }
  }

  /// 切換收藏狀態
  Future<void> _toggleFavorite() async {
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    await DatabaseService.toggleFavorite(
      widget.question.id,
      userId: userStateProvider.effectiveUserId,
    );
    if (mounted) {
      setState(() {
        _isFavorite = !_isFavorite;
      });
      // 按钮的变色已经算做提示，不需要额外的文字提示
    }
  }

  /// 構建圖片組件（優化：使用緩存避免內存抖動）
  /// 圖片已在外層容器中固定高度，這裡只負責圖片內容的顯示
  Widget _buildImageWidget(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) {
      return const SizedBox.shrink();
    }

    // 處理圖片路徑：如果是網絡URL則使用 Image.network，否則嘗試從 assets 加載
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.contain, // 使用 contain 模式，確保圖片完整顯示在固定高度內
        width: double.infinity, // 寬度占滿
        // 啟用緩存以避免重複下載
        cacheWidth: 800, // 限制圖片寬度，減少內存占用
        errorBuilder: (context, error, stackTrace) {
          return _buildImageError();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
      );
    } else {
      // 本地路徑，嘗試從 assets 加載
      // 數據庫中的路徑格式：/img_sign/550.png
      // assets 中的路徑格式：images/img_sign/550.png
      String assetPath = imagePath;

      // 移除開頭的 /
      if (assetPath.startsWith('/')) {
        assetPath = assetPath.substring(1);
      }

      // 如果路徑是 img_sign/xxx.png，轉換為 images/img_sign/xxx.png
      if (assetPath.startsWith('img_sign/')) {
        assetPath = 'images/$assetPath';
      }

      // 優化：使用 cacheWidth 限制圖片內存占用，Flutter 會自動緩存
      // Image.asset 已經自帶緩存機制，但設置 cacheWidth 可以減少內存占用
      return Image.asset(
        assetPath,
        fit: BoxFit.contain, // 使用 contain 模式，確保圖片完整顯示在固定高度內
        width: double.infinity, // 寬度占滿
        cacheWidth: 800, // 限制最大寬度為 800px，減少內存占用
        errorBuilder: (context, error, stackTrace) {
          return _buildImageError();
        },
        // 添加載入指示器（雖然 assets 加載很快，但為了用戶體驗）
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: frame != null
                ? child
                : const Center(child: CircularProgressIndicator()),
          );
        },
      );
    }
  }

  /// 圖片加載錯誤時的顯示
  Widget _buildImageError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.image_not_supported,
          size: 100,
          color: AppTheme.mutedFor(context),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.get('image_load_failed'),
          style: TextStyle(color: AppTheme.mutedFor(context)),
        ),
      ],
    );
  }

  /// 动画卡片滑出屏幕
  void _animateCardOut(double targetOffset, VoidCallback onComplete) {
    if (_dragAnimationController == null) return;

    _dragAnimation = Tween<double>(
      begin: _dragOffset,
      end: targetOffset,
    ).animate(CurvedAnimation(
      parent: _dragAnimationController!,
      curve: Curves.easeIn,
    ));

    _dragAnimationController!.forward().then((_) {
      onComplete();
    });
  }

  /// 动画卡片回弹到原位
  void _animateCardBack() {
    if (_dragAnimationController == null) return;

    _dragAnimation = Tween<double>(
      begin: _dragOffset,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _dragAnimationController!,
      curve: Curves.easeOut,
    ));

    _dragAnimationController!.forward().then((_) {
      _resetDragState();
    });
  }

  /// 重置拖拽状态
  void _resetDragState() {
    setState(() {
      _dragOffset = 0.0;
    });
    _dragAnimationController?.reset();
  }

  @override
  Widget build(BuildContext context) {
    // 使用 context.watch 實時監聽語言變化，確保語言切換時整個 Widget 重建
    final currentLang = context.watch<UserStateProvider>().currentLanguage;

    // 默認顯示意大利語題目
    final questionTextIt = widget.question.getDisplayQuestionText(
      defaultText: AppStrings.getWithLanguage(
        currentLang,
        'question_content_missing',
      ),
    );

    // 獲取翻譯語言的題目內容（如果存在）
    final questionTextTranslation = widget.currentLanguage != 'it'
        ? widget.question.getQuestionText(widget.currentLanguage)
        : null;

    // 獲取當前語言的解析內容
    final explanationText =
        widget.question.getExplanationText(widget.currentLanguage);

    // Stitch 设计稿布局：主要内容在滚动区域，右侧悬浮按钮，底部固定按钮
    return GestureDetector(
      // 检测水平拖拽开始
      onHorizontalDragStart: (details) {
        _dragAnimationController?.stop();
        _dragAnimationController?.reset();
      },
      // 检测水平拖拽更新（卡片跟随手指移动）
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragOffset += details.delta.dx;
          // 限制拖拽范围，防止过度拖拽
          final screenWidth = MediaQuery.of(context).size.width;
          _dragOffset =
              _dragOffset.clamp(-screenWidth * 0.8, screenWidth * 0.8);
        });
      },
      // 检测水平拖拽结束（决定是否切换题目）
      onHorizontalDragEnd: (details) {
        final screenWidth = MediaQuery.of(context).size.width;
        final velocity = details.primaryVelocity ?? 0;
        final dragDistance = _dragOffset.abs();
        final dragThreshold = screenWidth * 0.3; // 30% 屏幕宽度作为切换阈值

        // 判断是否切换题目：滑动距离超过阈值 或 滑动速度足够快
        bool shouldSwitch =
            dragDistance > dragThreshold || velocity.abs() > 500;

        if (shouldSwitch) {
          // 切换题目
          if (_dragOffset > 0 &&
              widget.hasPreviousQuestion &&
              widget.onPreviousQuestion != null) {
            // 向右拖拽：上一题
            _animateCardOut(screenWidth, () {
              widget.onPreviousQuestion!();
              _resetDragState();
            });
          } else if (_dragOffset < 0 &&
              widget.hasNextQuestion &&
              widget.onNextQuestion != null) {
            // 向左拖拽：下一题
            _animateCardOut(-screenWidth, () {
              widget.onNextQuestion!();
              _resetDragState();
            });
          } else {
            // 无法切换，回弹
            _animateCardBack();
          }
        } else {
          // 不切换，回弹到原位
          _animateCardBack();
        }
      },
      child: Container(
        decoration: AppTheme.pageDecorationFor(context),
        // 内容与操作按钮各占独立空间，互不遮挡：
        // iOS / Android 手机均在行尾一侧竖排（LTR 在右，RTL 在左），内容区让出这一列。
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final actions = _buildFloatingButtons(
                      context, currentLang, questionTextIt);
                  final content = AnimatedBuilder(
                    animation: _dragAnimationController ??
                        const AlwaysStoppedAnimation(0.0),
                    builder: (context, child) {
                      // 计算当前偏移量（拖拽中或动画中）
                      final currentOffset =
                          _dragAnimationController?.isAnimating == true
                              ? (_dragAnimation?.value ?? 0.0)
                              : _dragOffset;

                      return Transform.translate(
                        offset: Offset(currentOffset, 0),
                        child: Opacity(
                          // 根据拖拽距离调整透明度，增加视觉反馈
                          opacity: 1.0 -
                              (currentOffset.abs() /
                                      MediaQuery.of(context).size.width *
                                      0.3)
                                  .clamp(0.0, 0.3),
                          child: SingleChildScrollView(
                            key: ValueKey(
                                widget.question.id), // 使用题目ID作为key，确保题目变化时触发动画
                            controller: _scrollController,
                            // 卡片左右对称（与旧版一致居中）；按钮悬浮在卡片行尾内侧，
                            // 由卡片内边距为按钮让出位置，文字不会被遮挡。
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                20, 24, 20, 32),
                            child: _buildMainContent(
                              context,
                              questionTextIt,
                              questionTextTranslation,
                              explanationText,
                              currentLang,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                  // 反馈气泡浮在内容区底部，不越过侧边操作按钮区域。
                  return Stack(
                    children: [
                      Positioned.fill(child: content),
                      PositionedDirectional(
                        start: 0,
                        end: _actionRailEndInset + _actionRailWidth,
                        bottom: 16,
                        child: _buildFeedbackBubbles(),
                      ),
                      PositionedDirectional(
                        end: _actionRailEndInset,
                        bottom: 16,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: max(0, constraints.maxHeight - 32),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var k = 0; k < actions.length; k++) ...[
                                  if (k > 0) const SizedBox(height: 12),
                                  actions[k],
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            // 底部固定的 Vero/Falso 按钮
            _buildBottomButtons(context),
          ],
        ),
      ),
    );
  }

  /// 反馈气泡（精通、收藏、答对/答错），垂直排列，显示在内容区底部中间。
  /// 放在内容区内部，而不是底部按钮区，这样不会盖住侧边操作按钮。
  Widget _buildFeedbackBubbles() {
    return Padding(
      key: const ValueKey('question-feedback-bubbles'),
      // 两侧留边距；气泡内文字可换行，长语言或放大字号时不会横向溢出。
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 精通气泡（蓝色背景，最上方）
            if (widget.showMasteredBadge)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildMasteredBadge(),
              ),
            // 收藏气泡（蓝色背景）
            if (widget.showFavoriteBadge)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildFavoriteBadge(),
              ),
            // 对错提示气泡（最下方）
            // 如果显示精通气泡，则隐藏"正确"气泡
            if (widget.isAnswered &&
                widget.isCorrect != null &&
                !widget.hideCorrectBadge)
              _buildFeedbackBadge(),
          ],
        ),
      ),
    );
  }

  /// 构建主要内容区域
  Widget _buildMainContent(
    BuildContext context,
    String? questionTextIt,
    String? questionTextTranslation,
    String? explanationText,
    String currentLang,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return GlassCard(
      // 行尾多留出按钮列的宽度：卡片满宽居中，文字与图片不进入按钮下方。
      padding: const EdgeInsetsDirectional.fromSTEB(
          24, 24, _actionRailReserve - 20, 24),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题目文本（始终显示）
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              questionTextIt ?? AppStrings.get('question_content_missing'),
              // 意大利语题干始终从左到右排版（包括乌尔都语界面）。
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600, // SemiBold
                height: 1.4,
                letterSpacing: 0,
                color: colorScheme.onSurface,
              ),
            ),
          ),

          // 翻译展开后的布局（代码 B）
          if (_showTranslation) ...[
            // 翻译文本（如果存在）
            if (questionTextTranslation != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: TranslationPanel(
                  text: questionTextTranslation,
                  languageCode: currentLang,
                ),
              ),
            // 重点词汇（Chip 形式）- 始终显示（如果存在）
            // 使用 currentLang（从 Provider 实时获取），确保语言切换时能正确更新
            _buildKeyWordsChips(currentLang),
            const SizedBox(height: 32),
          ],

          // 图片
          if (widget.question.imageName != null &&
              widget.question.imageName!.isNotEmpty)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                maxHeight: 220,
              ),
              margin: EdgeInsets.only(top: _showTranslation ? 0.0 : 16.0),
              decoration: BoxDecoration(
                color: colorScheme.surface.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.35),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: _buildImageWidget(widget.question.imageName),
                  ),
                ),
              ),
            ),

          // 解析内容（如果展开）
          if (!widget.isExamMode &&
              _showExplanation &&
              explanationText != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primarySoftFor(context),
                borderRadius: AppTheme.isRetroFor(context)
                    ? BorderRadius.zero
                    : BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryFor(context).withOpacity(0.22),
                ),
              ),
              child: Text(
                explanationText,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建重点词汇 Chips
  Widget _buildKeyWordsChips(String currentLang) {
    final keyWords = widget.question.getKeyWords(currentLang);
    final mutedColor = AppTheme.mutedFor(context);
    final lineColor = AppTheme.lineFor(context);
    final isRetro = AppTheme.isRetroFor(context);

    // 🔍 调试：打印关键词信息
    if (kDebugMode) {
      if (keyWords.isEmpty) {
      } else {}
    }

    if (keyWords.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppStrings.getWithLanguage(currentLang, 'key_vocabulary'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: mutedColor,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 1,
                color: lineColor.withOpacity(0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: keyWords.map((keyword) {
                final itWord = keyword['it'] ?? '';
                final translation = keyword[currentLang] ??
                    keyword['en'] ??
                    keyword['zh'] ??
                    '';

                return ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(
                            0.8,
                          ),
                      borderRadius: isRetro
                          ? BorderRadius.zero
                          : BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withOpacity(0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .shadow
                              .withOpacity(0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          itWord,
                          // 意大利语词始终从左到右排版（乌尔都语界面下“A.B.S.”的句点不跑到左边）。
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        if (translation.isNotEmpty) ...[
                          Text(
                            '•',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          Text(
                            translation,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  /// 构建右侧悬浮按钮
  /// 题目操作按钮（收藏、朗读、解析、翻译）；摆放位置由 build 中的布局决定。
  List<Widget> _buildFloatingButtons(
    BuildContext context,
    String currentLang,
    String questionTextIt,
  ) {
    // 模拟考试模式下，只显示收藏按钮，不显示翻译和解析按钮
    if (widget.isExamMode) {
      return [
        // 收藏按钮（考试模式下仍然保留）
        _buildFloatingButton(
          icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
          label: AppStrings.getWithLanguage(currentLang, 'favorite'),
          onTap: _toggleFavorite,
          isActive: _isFavorite,
          toggled: _isFavorite,
        ),
      ];
    }

    // 练习模式下，显示所有按钮
    return [
          // 收藏按钮
          _buildFloatingButton(
            icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
            label: AppStrings.getWithLanguage(currentLang, 'favorite'),
            onTap: _toggleFavorite,
            isActive: _isFavorite,
            toggled: _isFavorite,
          ),
          // 朗讀按鈕：只朗讀意大利語原文，模擬考場音頻按鈕體驗
          _buildFloatingButton(
            icon: _isPreparingSpeech
                ? Icons.hourglass_top_rounded
                : _isSpeakingQuestion
                    ? Icons.stop_circle_outlined
                    : Icons.volume_up_outlined,
            label: AppStrings.getWithLanguage(
              currentLang,
              _isPreparingSpeech
                  ? 'speech_preparing'
                  : _isSpeakingQuestion
                      ? 'speech_stop'
                      : 'listen_question',
            ),
            onTap: () {
              _toggleQuestionSpeech(questionTextIt, currentLang);
            },
            isActive: _isSpeakingQuestion || _isPreparingSpeech,
          ),
          // 解析按钮
          _buildFloatingButton(
            icon: _showExplanation ? Icons.menu_book : Icons.menu_book_outlined,
            label: AppStrings.getWithLanguage(currentLang, 'btn_explanation'),
            onTap: () {
              _showRichExplanation(context);
            },
            isActive: _showExplanation,
          ),
          // 翻译按钮
          if (widget.currentLanguage != 'it' &&
              widget.question.getQuestionText(widget.currentLanguage) != null)
            _buildFloatingButton(
              icon: Icons.translate,
              label: AppStrings.getWithLanguage(currentLang, 'translation'),
              onTap: () {
                setState(() {
                  _showTranslation = !_showTranslation;
                  if (!_showTranslation) {
                    _showExplanation = false;
                  }
                });
                _notifyReadingChanged();
              },
              isActive: _showTranslation,
              toggled: _showTranslation,
            ),
    ];
  }

  /// 顯示高保質感解析底部彈窗（委託給靜態方法，便於全 App 複用）
  Future<void> _showRichExplanation(BuildContext context) async {
    if (_isExplanationOpen) return;
    _isExplanationOpen = true;
    _notifyReadingChanged();
    try {
      await _openRichExplanation(context);
    } finally {
      _isExplanationOpen = false;
      if (mounted) _notifyReadingChanged();
    }
  }

  Future<void> _openRichExplanation(BuildContext context) async {
    await QuestionWidget.showRichExplanation(
      context,
      question: widget.question,
      currentLanguage: widget.currentLanguage,
    );
  }

  Future<void> _toggleQuestionSpeech(
    String questionText,
    String currentLang,
  ) async {
    if (_isPreparingSpeech || _isSpeakingQuestion) {
      _speechSession++;
      await _speechService.stop();
      if (mounted) {
        setState(() {
          _isSpeakingQuestion = false;
          _isPreparingSpeech = false;
        });
      }
      return;
    }

    final session = ++_speechSession;
    if (mounted) {
      setState(() => _isPreparingSpeech = true);
    }

    try {
      var preferNaturalAudio = true;
      final shouldOfferPack =
          await _speechService.shouldOfferVoicePack(widget.question.id);
      if (!mounted || session != _speechSession) return;

      if (shouldOfferPack) {
        final manageVoicePacks = await _showVoicePackChoice(currentLang);
        if (!mounted || session != _speechSession) return;
        if (manageVoicePacks == null) {
          setState(() => _isPreparingSpeech = false);
          return;
        }
        if (manageVoicePacks) {
          setState(() => _isPreparingSpeech = false);
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const VoicePackScreen(),
            ),
          );
          return;
        }

        await _speechService.rememberSystemVoiceChoice();
        preferNaturalAudio = false;
      }

      var stoppedBeforeStartReturned = false;
      final started = await _speechService.speakItalian(
        questionText,
        questionId: widget.question.id,
        preferNaturalAudio: preferNaturalAudio,
        onStart: () {
          if (mounted && session == _speechSession) {
            setState(() {
              _isPreparingSpeech = false;
              _isSpeakingQuestion = true;
            });
          }
        },
        onStop: () {
          stoppedBeforeStartReturned = true;
          if (mounted && session == _speechSession) {
            setState(() {
              _isSpeakingQuestion = false;
              _isPreparingSpeech = false;
            });
          }
        },
      );

      if (!mounted || session != _speechSession) return;
      if (started && !stoppedBeforeStartReturned) {
        setState(() {
          _isPreparingSpeech = false;
          _isSpeakingQuestion = true;
        });
      } else if (!started) {
        _showSpeechUnavailableMessage(currentLang);
      }
    } catch (_) {
      if (mounted && session == _speechSession) {
        setState(() {
          _isPreparingSpeech = false;
          _isSpeakingQuestion = false;
        });
        _showSpeechUnavailableMessage(currentLang);
      }
    } finally {
      if (mounted && session == _speechSession && _isPreparingSpeech) {
        setState(() => _isPreparingSpeech = false);
      }
    }
  }

  /// true：前往管理語音包；false：沿用系統語音；null：取消。
  Future<bool?> _showVoicePackChoice(String currentLang) {
    return showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final isRetro = AppTheme.isRetroFor(sheetContext);
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: isRetro
                ? BorderRadius.zero
                : const BorderRadius.vertical(top: Radius.circular(24)),
            border: isRetro ? Border.all(color: AppTheme.retroLine) : null,
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            MediaQuery.viewPaddingOf(sheetContext).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: isRetro
                        ? BorderRadius.zero
                        : BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Icon(
                Icons.graphic_eq_rounded,
                size: 38,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                AppStrings.getWithLanguage(
                    currentLang, 'voice_pack_prompt_title'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.getWithLanguage(
                    currentLang, 'voice_pack_prompt_message'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  AppStrings.getWithLanguage(currentLang, 'voice_pack_manage'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: Text(
                  AppStrings.getWithLanguage(
                      currentLang, 'voice_pack_use_system_voice'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSpeechUnavailableMessage(String currentLang) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.getWithLanguage(currentLang, 'speech_unavailable'),
        ),
      ),
    );
  }

  /// 构建单个悬浮按钮
  Widget _buildFloatingButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    bool? toggled,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final primaryColor = AppTheme.primaryFor(context);
    // 读屏：报为按钮；收藏、翻译这类开关同时报出当前是否已开启。
    return Semantics(
      button: true,
      toggled: toggled,
      child: GestureDetector(
        onTap: onTap,
        child: GlassCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(48),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color:
                  isActive ? primaryColor.withOpacity(0.12) : Colors.transparent,
              border: isActive
                  ? Border.all(
                      color: primaryColor.withOpacity(0.3),
                      width: 1,
                    )
                  : null,
              borderRadius:
                  isRetro ? BorderRadius.zero : BorderRadius.circular(48),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? primaryColor : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 42,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                        color: isActive
                            ? primaryColor
                            : colorScheme.onSurfaceVariant,
                      ),
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

  /// 构建底部固定按钮
  Widget _buildBottomButtons(BuildContext context) {
    final buttons = Row(
      children: [
        Expanded(
          child: _buildAnswerButton(
            context: context,
            label: 'VERO',
            isVero: true,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildAnswerButton(
            context: context,
            label: 'FALSO',
            isVero: false,
          ),
        ),
      ],
    );
    // 道路主題的按鈕帶厚底陰影；外層若再裁切（毛玻璃）會把陰影底部切平，
    // 而這層背景本就透明，因此道路主題下直接不裁切。
    final isRoad = AppTheme.usesRoadPalette && !AppTheme.isRetroFor(context);
    return SafeArea(
      child: Stack(
        clipBehavior: Clip.none, // 允许气泡向上弹出，不被父容器遮挡
        children: [
          Container(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: 16,
            ),
            // 移除白色背景，只保留透明背景
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            child: isRoad
                ? buttons
                : ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: buttons,
                    ),
                  ),
          ),
        ],
      ),
    );
  }


  /// 构建答案按钮
  Widget _buildAnswerButton({
    required BuildContext context,
    required String label,
    required bool isVero,
  }) {
    // 判断按钮是否被用户选中
    final displayedChoice = widget.userChoice ?? widget.selectedAnswer;
    final isSelected = widget.isAnswered && displayedChoice == isVero;

    if (AppTheme.usesRoadPalette && !AppTheme.isRetroFor(context)) {
      return _buildRoadAnswerButton(
        context: context,
        label: label,
        isVero: isVero,
        isSelected: isSelected,
        displayedChoice: displayedChoice,
      );
    }

    // 按钮背景色：如果已答题且被选中，变为主题主色；否则为表面色。
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final buttonColor = isSelected ? colorScheme.primary : colorScheme.surface;

    // 文字颜色由主题决定，避免夜间/复古模式固定使用白色或深灰色。
    final textColor =
        isSelected ? colorScheme.onPrimary : colorScheme.onSurface;

    return GestureDetector(
      onTap: widget.isAnswered ? null : () => widget.onAnswerSelected(isVero),
      child: AnimatedScale(
        scale: isSelected ? 1.01 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 70, // 固定高度
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius:
                isRetro ? BorderRadius.zero : BorderRadius.circular(24),
            boxShadow: isRetro
                ? const []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(isSelected ? 0.09 : 0.05),
                      blurRadius: isSelected ? 10 : 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 18, // 字号18
                fontWeight: FontWeight.w700, // 字重w700
                color: textColor,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 道路主題的答題按鈕：厚底、粗描邊；作答後直接在按鈕上標出對錯，
  /// 答錯時同時把正確選項標綠，不另外彈出需要點擊的卡片，保持自動跳題節奏。
  Widget _buildRoadAnswerButton({
    required BuildContext context,
    required String label,
    required bool isVero,
    required bool isSelected,
    required bool? displayedChoice,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = AppTheme.inkFor(context);
    final success = AppTheme.successFor(context);
    final danger = AppTheme.dangerFor(context);
    final hasVerdict = widget.isAnswered &&
        widget.isCorrect != null &&
        displayedChoice != null;
    final correctChoice = hasVerdict
        ? (widget.isCorrect! ? displayedChoice : !displayedChoice)
        : null;
    final isCorrectOption = hasVerdict && correctChoice == isVero;
    final isWrongPick = hasVerdict && isSelected && !widget.isCorrect!;

    Color background = AppTheme.surfaceFor(context);
    Color foreground = ink;
    Color border = AppTheme.lineFor(context);
    Color shadow = AppTheme.lineFor(context);
    IconData? icon;
    if (isCorrectOption) {
      background = success;
      foreground = isDark ? AppTheme.roadNightPage : Colors.white;
      border = isDark ? success : AppTheme.roadPrimaryDark;
      shadow = isDark ? Colors.black : AppTheme.roadPrimaryDark;
      icon = Icons.check_rounded;
    } else if (isWrongPick) {
      foreground = danger;
      border = danger;
      shadow = danger.withOpacity(0.35);
      icon = Icons.close_rounded;
    } else if (isSelected) {
      // 無對錯資訊時（例如回看已選答案）只標記選擇。
      background = AppTheme.primaryFor(context);
      foreground = isDark ? AppTheme.roadNightPage : Colors.white;
      border = background;
      shadow = isDark ? Colors.black : AppTheme.roadPrimaryDark;
    } else if (hasVerdict) {
      foreground = AppTheme.mutedFor(context);
    }

    return Semantics(
      button: true,
      enabled: !widget.isAnswered,
      selected: isSelected,
      child: GestureDetector(
        onTap: widget.isAnswered ? null : () => widget.onAnswerSelected(isVero),
        // 按下回彈 + 對錯動效：答對的按鈕彈起，選錯的按鈕輕抖。
        child: BouncyPress(
          enabled: !widget.isAnswered,
          child: AnswerMotion(
            kind: hasVerdict && isSelected
                ? (widget.isCorrect!
                    ? AnswerMotionKind.correctPop
                    : AnswerMotionKind.wrongShake)
                : AnswerMotionKind.none,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              height: 66,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: border, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: shadow,
                    blurRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 22, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: foreground,
                      letterSpacing: 1.2,
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

  /// 构建反馈标签（Badge）
  Widget _buildFeedbackBadge() {
    if (!widget.isAnswered || widget.isCorrect == null) {
      return const SizedBox.shrink();
    }

    // 使用短距淡入，避免大幅回彈造成整個畫面像閃了一下。
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final opacityValue = value.clamp(0.0, 1.0).toDouble();
        final isRetro = AppTheme.isRetroFor(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final isRoad = AppTheme.usesRoadPalette && !isRetro;
        // 道路主題：答錯用深墨色而非大紅，語氣溫和，並直接告訴正確答案。
        final feedbackBackground = isRoad
            ? widget.isCorrect!
                ? (isDark
                    ? AppTheme.roadNightPrimarySoft
                    : AppTheme.roadPrimary)
                : (isDark ? AppTheme.roadNightSurfaceAlt : AppTheme.roadInk)
            : widget.isCorrect!
                ? isRetro
                    ? AppTheme.retroPrimary
                    : isDark
                        ? const Color(0xFF14532D)
                        : const Color(0xFF166534)
                : isRetro
                    ? AppTheme.retroDanger
                    : isDark
                        ? const Color(0xFF7F1D1D)
                        : const Color(0xFFB91C1C);
        final feedbackForeground = isRetro
            ? AppTheme.retroPage
            : isRoad
                ? Colors.white
                : isDark
                    ? (widget.isCorrect!
                        ? const Color(0xFFD1FAE5)
                        : const Color(0xFFFECACA))
                    : Colors.white;
        final displayedChoice = widget.userChoice ?? widget.selectedAnswer;
        final feedbackLabel = widget.isCorrect!
            ? AppStrings.getWithLanguage(widget.currentLanguage, 'correct')
            : isRoad && displayedChoice != null
                ? AppStrings.getWithLanguage(
                    widget.currentLanguage,
                    'answer_feedback_wrong_gentle',
                  ).replaceAll('{answer}', displayedChoice ? 'FALSO' : 'VERO')
                : AppStrings.getWithLanguage(widget.currentLanguage, 'wrong');
        return Opacity(
          opacity: opacityValue,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: Transform.scale(
              scale: 0.96 + (0.04 * value),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: feedbackBackground,
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(20),
                  border: isRetro
                      ? Border.all(color: AppTheme.retroLine)
                      : isRoad && isDark
                          ? Border.all(
                              color: widget.isCorrect!
                                  ? AppTheme.roadNightPrimary
                                  : AppTheme.roadNightLine,
                            )
                          : null,
                  boxShadow: isRetro
                      ? const []
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(
                              0.15 * opacityValue,
                            ), // 阴影也跟随动画
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isCorrect! ? Icons.check : Icons.close,
                          color: isRoad && widget.isCorrect!
                              ? AppTheme.roadAccent
                              : feedbackForeground,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            feedbackLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: feedbackForeground,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.isCorrect!) ...[
                      const SizedBox(height: 6),
                      _buildCorrectMomentum(opacityValue),
                    ],
                    // 错题已彻底消灭提示
                    if (widget.isCorrect! && widget.mistakeEliminated) ...[
                      const SizedBox(height: 4),
                      Text(
                        AppStrings.getWithLanguage(widget.currentLanguage,
                            'mistake_cleared_celebration'),
                        style: TextStyle(
                          color: feedbackForeground,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 以短標籤和 3 格進度呈現本次連對與單題掌握度。
  Widget _buildCorrectMomentum(double animationValue) {
    final safeAnimationValue = animationValue.clamp(0.0, 1.0).toDouble();
    final isRetro = AppTheme.isRetroFor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final feedbackForeground = isRetro
        ? AppTheme.retroPage
        : isDark
            ? const Color(0xFFD1FAE5)
            : Colors.white;
    // 連對分檔：3 起火焰變大變橙，5 起徽章轉橙紅漸層並發光，10 起火力全開。
    final streak = widget.sessionCorrectStreak;
    final isRoad = AppTheme.usesRoadPalette && !isRetro;
    final tier = !isRoad
        ? 0
        : streak >= 10
            ? 3
            : streak >= 5
                ? 2
                : streak >= 3
                    ? 1
                    : 0;
    const tierFlameColors = [
      Color(0xFFFFC247),
      Color(0xFFFF9F1C),
      Color(0xFFFFE08A),
      Color(0xFFFFF3C4),
    ];
    final flameColor =
        isRetro ? feedbackForeground : tierFlameColors[tier];
    final flameSize = const [18.0, 24.0, 30.0, 36.0][tier];
    final streakFontSize = const [12.0, 14.0, 17.0, 20.0][tier];
    final masteryStep = widget.questionMasteryStep.clamp(0, 3).toInt();
    final streakLabel = AppStrings.getWithLanguage(
      widget.currentLanguage,
      'answer_streak_short',
    ).replaceAll('{count}', '${widget.sessionCorrectStreak}');
    final masteryLabel = AppStrings.getWithLanguage(
      widget.currentLanguage,
      'question_mastery_progress_short',
    ).replaceAll('{current}', '$masteryStep').replaceAll('{total}', '3');
    final semanticParts = <String>[
      if (widget.sessionCorrectStreak >= 1) streakLabel,
      masteryLabel,
    ];

    return Semantics(
      label: semanticParts.join(', '),
      child: ExcludeSemantics(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 5,
          children: [
            if (widget.sessionCorrectStreak >= 1)
              StreakJitter(
                strength: tier >= 3 ? 2 : (tier >= 2 ? 1 : 0),
                child: Container(
                key: ValueKey('streak-chip-tier-$tier'),
                padding: EdgeInsets.symmetric(
                  horizontal: tier >= 2 ? 12 : 7,
                  vertical: tier >= 2 ? 5 : 3,
                ),
                decoration: BoxDecoration(
                  color: tier >= 2 ? null : feedbackForeground.withOpacity(0.18),
                  // 黃→橙→紅的亮色漸層，連對越多越紅越亮。
                  gradient: tier >= 2
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: tier >= 3
                              ? const [
                                  Color(0xFFFFD43B),
                                  Color(0xFFFF7A00),
                                  Color(0xFFFF1E00),
                                ]
                              : const [
                                  Color(0xFFFFE066),
                                  Color(0xFFFF9F1C),
                                  Color(0xFFFF5A1F),
                                ],
                        )
                      : null,
                  border: tier >= 2
                      ? Border.all(
                          color: const Color(0xFFFFF3C4).withOpacity(0.9),
                          width: 1.5,
                        )
                      : null,
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(999),
                  boxShadow: tier >= 2
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF7A00)
                                .withOpacity(tier >= 3 ? 0.9 : 0.65),
                            blurRadius: tier >= 3 ? 24 : 14,
                            spreadRadius: tier >= 3 ? 2 : 0,
                          ),
                          if (tier >= 3)
                            const BoxShadow(
                              color: Color(0x66FFD43B),
                              blurRadius: 36,
                              spreadRadius: 4,
                            ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      key: ValueKey<String>(
                        'streak-flame-${widget.question.id}-${widget.sessionCorrectStreak}',
                      ),
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 520),
                      builder: (context, value, child) {
                        final scale = switch (value) {
                          <= 0.42 => 0.62 +
                              (0.8 *
                                  Curves.easeOutCubic.transform(value / 0.42)),
                          <= 0.72 => 1.42 -
                              (0.5 *
                                  Curves.easeInOut.transform(
                                    (value - 0.42) / 0.3,
                                  )),
                          _ => 0.92 +
                              (0.08 *
                                  Curves.easeOutCubic.transform(
                                    (value - 0.72) / 0.28,
                                  )),
                        };

                        double rotation;
                        if (value <= 0.22) {
                          rotation =
                              -0.16 * Curves.easeOut.transform(value / 0.22);
                        } else if (value <= 0.5) {
                          rotation = -0.16 +
                              (0.3 *
                                  Curves.easeInOut.transform(
                                    (value - 0.22) / 0.28,
                                  ));
                        } else {
                          rotation = 0.14 *
                              (1 -
                                  Curves.easeOut.transform(
                                    (value - 0.5) / 0.5,
                                  ));
                        }

                        final lift = value <= 0.42
                            ? 3 - (5 * (value / 0.42))
                            : -2 + (2 * ((value - 0.42) / 0.58));
                        return Transform.translate(
                          offset: Offset(0, lift),
                          child: Transform.rotate(
                            angle: rotation,
                            child: Transform.scale(scale: scale, child: child),
                          ),
                        );
                      },
                      child: Icon(
                        Icons.local_fire_department_rounded,
                        color: flameColor,
                        size: flameSize,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      streakLabel,
                      style: TextStyle(
                        color: feedbackForeground,
                        fontSize: streakFontSize,
                        fontWeight:
                            tier >= 2 ? FontWeight.w900 : FontWeight.w700,
                        shadows: tier >= 2
                            ? const [
                                Shadow(
                                  color: Color(0xCC9A1B00),
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  masteryLabel,
                  style: TextStyle(
                    color: feedbackForeground,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                ...List.generate(3, (index) {
                  final isFilled = index < masteryStep;
                  return Container(
                    width: 15,
                    height: 5,
                    margin: EdgeInsets.only(right: index == 2 ? 0 : 3),
                    decoration: BoxDecoration(
                      color: isFilled
                          ? feedbackForeground.withOpacity(
                              0.45 + (0.55 * safeAnimationValue),
                            )
                          : feedbackForeground.withOpacity(0.25),
                      borderRadius: isRetro
                          ? BorderRadius.zero
                          : BorderRadius.circular(999),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建收藏气泡（Badge）
  Widget _buildFavoriteBadge() {
    // 使用 TweenAnimationBuilder 实现流畅的入场动画
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final isRetro = AppTheme.isRetroFor(context);
        final primaryColor = AppTheme.primaryFor(context);
        final foregroundColor = Theme.of(context).colorScheme.onPrimary;
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - value)),
            child: Transform.scale(
              scale: 0.8 + (0.2 * value),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(20),
                  boxShadow: isRetro
                      ? const []
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15 * value),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite,
                      color: isRetro ? AppTheme.retroPage : foregroundColor,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        AppStrings.getWithLanguage(
                            widget.currentLanguage, 'favorited'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              isRetro ? AppTheme.retroPage : foregroundColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建精通气泡（Badge）
  Widget _buildMasteredBadge() {
    // 精通提示也保持短距、無回彈，避免連答時產生閃動。
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final opacityValue = value.clamp(0.0, 1.0).toDouble();
        final isRetro = AppTheme.isRetroFor(context);
        final primaryColor = AppTheme.primaryFor(context);
        final foregroundColor = Theme.of(context).colorScheme.onPrimary;
        return Opacity(
          opacity: opacityValue,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: Transform.scale(
              scale: 0.96 + (0.04 * value),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(20),
                  boxShadow: isRetro
                      ? const []
                      : [
                          BoxShadow(
                            color:
                                Colors.black.withOpacity(0.15 * opacityValue),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star,
                          color: isRetro ? AppTheme.retroPage : foregroundColor,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            AppStrings.getWithLanguage(
                                widget.currentLanguage, 'mastered_badge_short'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isRetro
                                  ? AppTheme.retroPage
                                  : foregroundColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildCorrectMomentum(opacityValue),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
