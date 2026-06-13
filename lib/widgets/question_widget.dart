import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import 'dart:ui';
import '../models/question.dart';
import '../services/database_service.dart';
import '../services/explanation_parser.dart';
import '../services/question_speech_service.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../providers/user_state_provider.dart';
import '../screens/subscription_page.dart';
import 'glass_card.dart';
import 'translation_panel.dart';

/// 題目顯示組件
/// 負責顯示題目內容、圖片、選項和解析
class QuestionWidget extends StatefulWidget {
  final Question question;
  final Function(bool) onAnswerSelected;
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

  const QuestionWidget({
    super.key,
    required this.question,
    required this.onAnswerSelected,
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
  });

  /// 全 App 統一的解析底部彈窗（練習、考後復盤等共用，自動識別 JSON / 純文本）
  /// [remainingExplanations] 傳入當前剩餘免費解析次數（僅非 VIP 顯示；為 null 時不顯示提示行）
  /// [showVipBadgeOnStudyTip] 為 true 時在學習小貼士區塊顯示「✨ VIP」標籤並可點擊跳轉訂閱頁（僅非 VIP 時傳 true）
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
    final keyPoints = parsedExplanation.keyPoints;
    final studyTip = parsedExplanation.studyTip;
    final isJsonFormat = parsedExplanation.isJsonFormat;

    // 內部工具：將文本中括號內內容用較淡顏色顯示，括號外保持主色
    TextSpan buildTextWithSoftParenthesis(
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

    TextSpan buildStudyTipMarkdownSpan(String text) {
      final normalStyle = TextStyle(
        fontSize: 14,
        height: 1.6,
        color: Colors.blue[900],
      );
      final boldKeywordStyle = TextStyle(
        fontSize: 14,
        height: 1.6,
        color: Colors.blue[700],
        fontWeight: FontWeight.w700,
      );
      final trueStyle = TextStyle(
        fontSize: 14,
        height: 1.6,
        color: Colors.green[700],
        fontWeight: FontWeight.w700,
      );
      final falseStyle = TextStyle(
        fontSize: 14,
        height: 1.6,
        color: Colors.red[600],
        fontWeight: FontWeight.w700,
      );
      final parenthesisStyle = TextStyle(
        fontSize: 14,
        height: 1.6,
        color: Colors.blue[400],
      );

      List<TextSpan> buildTokenSpans(String raw, TextStyle base) {
        final spans = <TextSpan>[];
        // 僅在「獨立詞」或「括號後的對/錯/正確」等高亮，避免「针对」「面对」「对不对」等誤判。
        // 順序：較長片段優先；單字「对/错/對」需排除常見詞內嵌。
        final tokenReg = RegExp(
          r'\b(?:Vero|Falso|True|False)\b'
          r'|(?<![\u4e00-\u9fff])错误(?![\u4e00-\u9fffA-Za-z0-9])'
          r'|(?<![\u4e00-\u9fff])錯誤(?![\u4e00-\u9fffA-Za-z0-9])'
          r'|(?<![\u4e00-\u9fff])正确(?![\u4e00-\u9fffA-Za-z0-9])'
          r'|(?<![\u4e00-\u9fff])正確(?![\u4e00-\u9fffA-Za-z0-9])'
          r'|(?<!针|針|面)对(?!不)(?![\u4e00-\u9fffA-Za-z0-9])'
          r'|(?<!针|針|面)對(?!不)(?![\u4e00-\u9fffA-Za-z0-9])'
          r'|(?<!不)错(?![\u4e00-\u9fffA-Za-z0-9])'
          r'|(?<!不)錯(?![\u4e00-\u9fffA-Za-z0-9])',
          caseSensitive: false,
        );
        int current = 0;
        for (final m in tokenReg.allMatches(raw)) {
          if (m.start > current) {
            spans.add(buildTextWithSoftParenthesis(
              raw.substring(current, m.start),
              base,
              parenthesisStyle,
            ));
          }
          final token = raw.substring(m.start, m.end);
          final lower = token.toLowerCase();
          bool isTrue;
          if (lower == 'vero' || lower == 'true') {
            isTrue = true;
          } else if (lower == 'falso' || lower == 'false') {
            isTrue = false;
          } else {
            var inner = token;
            if (inner.length >= 2 &&
                (inner.startsWith('(') || inner.startsWith('（')) &&
                (inner.endsWith(')') || inner.endsWith('）'))) {
              inner = inner.substring(1, inner.length - 1);
            }
            isTrue =
                inner == '正确' || inner == '正確' || inner == '对' || inner == '對';
          }
          spans.add(
              TextSpan(text: token, style: isTrue ? trueStyle : falseStyle));
          current = m.end;
        }
        if (current < raw.length) {
          spans.add(buildTextWithSoftParenthesis(
            raw.substring(current),
            base,
            parenthesisStyle,
          ));
        }
        return spans;
      }

      final spans = <TextSpan>[];
      final boldReg = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
      int index = 0;
      for (final m in boldReg.allMatches(text)) {
        if (m.start > index) {
          spans.addAll(
              buildTokenSpans(text.substring(index, m.start), normalStyle));
        }
        final boldText = m.group(1) ?? '';
        spans.addAll(buildTokenSpans(boldText, boldKeywordStyle));
        index = m.end;
      }
      if (index < text.length) {
        spans.addAll(buildTokenSpans(text.substring(index), normalStyle));
      }

      return TextSpan(style: normalStyle, children: spans);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        return ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.radiusXl),
            topRight: Radius.circular(AppTheme.radiusXl),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(bottomSheetContext).size.height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
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
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primary.withOpacity(0.22),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppStrings.getWithLanguage(currentLanguage,
                                    'modal_correct_answer_label'),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.ink,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Text(
                                    correctAnswer,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
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
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: buildTextWithSoftParenthesis(
                            detailedDescription,
                            const TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              color: AppTheme.ink,
                            ),
                            const TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              color: AppTheme.muted,
                            ),
                          ),
                        ),
                        if (isJsonFormat &&
                            keyPoints != null &&
                            keyPoints.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            AppStrings.getWithLanguage(
                                currentLanguage, 'key_points_title'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
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
                                    decoration: const BoxDecoration(
                                      color: AppTheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                          fontSize: 15,
                                          height: 1.5,
                                          color: AppTheme.ink,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: '${point['title']}：',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          TextSpan(
                                            text: point['content'] ?? '',
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
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _StudyTipSection(
                            showVipBadge: showVipBadgeOnStudyTip,
                            onTap: showVipBadgeOnStudyTip
                                ? () {
                                    Navigator.pop(bottomSheetContext);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const SubscriptionPage(),
                                      ),
                                    );
                                  }
                                : null,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.lightbulb_outline,
                                  color: AppTheme.warning,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: RichText(
                                    strutStyle: const StrutStyle(
                                      fontSize: 14,
                                      height: 1.6,
                                      leadingDistribution:
                                          TextLeadingDistribution.even,
                                    ),
                                    text: buildStudyTipMarkdownSpan(studyTip),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (remainingExplanations != null) ...[
                          Center(
                            child: Text(
                              '${AppStrings.getWithLanguage(currentLanguage, 'remaining_free_explanations')}: $remainingExplanations',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
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
    Widget content = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 48, 16),
          decoration: BoxDecoration(
            color: AppTheme.primarySoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.primary.withOpacity(0.22),
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
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '✨ VIP',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
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
          borderRadius: BorderRadius.circular(12),
          child: content,
        ),
      );
    }

    return content;
  }
}

class _QuestionWidgetState extends State<QuestionWidget>
    with SingleTickerProviderStateMixin {
  bool _showExplanation = false;
  bool _isFavorite = false;
  bool _showTranslation = false; // 翻譯顯示狀態
  bool _isSpeakingQuestion = false;
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
      _speechService.stop();
      setState(() {
        _showTranslation = false;
        _showExplanation = false;
        _isSpeakingQuestion = false;
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
        const Icon(
          Icons.image_not_supported,
          size: 100,
          color: Colors.grey,
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.get('image_load_failed'),
          style: const TextStyle(color: Colors.grey),
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
        decoration: AppTheme.pageDecoration,
        child: Stack(
          children: [
            // 主要内容区域（可滚动，带滑动卡片效果）
            Column(
              children: [
                Expanded(
                  child: AnimatedBuilder(
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
                            padding: const EdgeInsets.fromLTRB(
                                20, 24, 20, 180), // 底部留出空间给固定按钮
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
                  ),
                ),
                // 底部固定的 Vero/Falso 按钮
                _buildBottomButtons(context),
              ],
            ),
            // 右侧悬浮按钮
            _buildFloatingButtons(context, currentLang, questionTextIt),
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
    return GlassCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题目文本（始终显示）
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              questionTextIt ?? AppStrings.get('question_content_missing'),
              textAlign: TextAlign.left,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600, // SemiBold
                height: 1.4,
                letterSpacing: 0,
                color: AppTheme.ink,
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
                color: Colors.white.withOpacity(0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.5),
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
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withOpacity(0.22)),
              ),
              child: Text(
                explanationText,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.black87,
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
                color: Colors.grey[400],
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 1,
                color: Colors.grey[200],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: keyWords.map((keyword) {
            final itWord = keyword['it'] ?? '';
            final translation =
                keyword[currentLang] ?? keyword['en'] ?? keyword['zh'] ?? '';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.8),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    itWord,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '•',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    translation,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 构建右侧悬浮按钮
  Widget _buildFloatingButtons(
    BuildContext context,
    String currentLang,
    String questionTextIt,
  ) {
    // 模拟考试模式下，只显示收藏按钮，不显示翻译和解析按钮
    if (widget.isExamMode) {
      return Positioned(
        right: 20,
        bottom: 160, // 在底部按钮上方
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 收藏按钮（考试模式下仍然保留）
            _buildFloatingButton(
              icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
              label: AppStrings.getWithLanguage(currentLang, 'favorite'),
              onTap: _toggleFavorite,
              isActive: _isFavorite,
            ),
          ],
        ),
      );
    }

    // 练习模式下，显示所有按钮
    return Positioned(
      right: 20,
      bottom: 160, // 在底部按钮上方
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 收藏按钮
          _buildFloatingButton(
            icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
            label: AppStrings.getWithLanguage(currentLang, 'favorite'),
            onTap: _toggleFavorite,
            isActive: _isFavorite,
          ),
          const SizedBox(height: 12),
          // 朗讀按鈕：只朗讀意大利語原文，模擬考場音頻按鈕體驗
          _buildFloatingButton(
            icon: _isSpeakingQuestion
                ? Icons.stop_circle_outlined
                : Icons.volume_up_outlined,
            label: AppStrings.getWithLanguage(currentLang, 'listen_question'),
            onTap: () {
              _toggleQuestionSpeech(questionTextIt, currentLang);
            },
            isActive: _isSpeakingQuestion,
          ),
          const SizedBox(height: 12),
          // 解析按钮
          _buildFloatingButton(
            icon: _showExplanation ? Icons.menu_book : Icons.menu_book_outlined,
            label: AppStrings.getWithLanguage(currentLang, 'btn_explanation'),
            onTap: () {
              _showRichExplanation(context);
            },
            isActive: _showExplanation,
          ),
          const SizedBox(height: 12),
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
              },
              isActive: _showTranslation,
            ),
        ],
      ),
    );
  }

  /// 顯示高保質感解析底部彈窗（委託給靜態方法，便於全 App 複用）
  Future<void> _showRichExplanation(BuildContext context) async {
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    final isVip = userStateProvider.isVip;
    final questionId = widget.question.id;

    if (!userStateProvider.canViewExplanation(questionId)) {
      // 今日免費解析次數已用完：引導跳轉訂閱頁
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.getWithLanguage(
                widget.currentLanguage, 'explanation_limit_reached_message'),
          ),
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
      question: widget.question,
      currentLanguage: widget.currentLanguage,
      remainingExplanations:
          (!isVip && !alreadyUnlockedToday) ? remainingBefore : null,
      showVipBadgeOnStudyTip: !isVip,
    );

    // 非 VIP 用戶在成功查看後遞增一次計數
    if (!isVip && !alreadyUnlockedToday) {
      await userStateProvider.incrementExplanationCount(questionId);
    }
  }

  Future<void> _toggleQuestionSpeech(
    String questionText,
    String currentLang,
  ) async {
    if (_isSpeakingQuestion) {
      await _speechService.stop();
      if (mounted) {
        setState(() {
          _isSpeakingQuestion = false;
        });
      }
      return;
    }

    try {
      final started = await _speechService.speakItalian(
        questionText,
        onStart: () {
          if (mounted) {
            setState(() {
              _isSpeakingQuestion = true;
            });
          }
        },
        onStop: () {
          if (mounted) {
            setState(() {
              _isSpeakingQuestion = false;
            });
          }
        },
      );

      if (mounted && started) {
        setState(() {
          _isSpeakingQuestion = true;
        });
      } else if (mounted) {
        _showSpeechUnavailableMessage(currentLang);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSpeakingQuestion = false;
        });
        _showSpeechUnavailableMessage(currentLang);
      }
    }
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(48),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.primary.withOpacity(0.12)
                : Colors.transparent,
            border: isActive
                ? Border.all(
                    color: AppTheme.primary.withOpacity(0.3),
                    width: 1,
                  )
                : null,
            borderRadius: BorderRadius.circular(48),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive ? AppTheme.primary : const Color(0xFF475569),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? AppTheme.primary : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建底部固定按钮
  Widget _buildBottomButtons(BuildContext context) {
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
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildAnswerButton(
                        label: 'VERO',
                        isVero: true,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildAnswerButton(
                        label: 'FALSO',
                        isVero: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 反馈气泡（在两个按钮上方中间位置，确保高于按钮）
          // 垂直排列多个气泡，避免重叠
          Positioned(
            bottom: 120, // 按钮高度(70) + 上方间距(50)，确保气泡高于按钮
            left: 0,
            right: 0,
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
          ),
        ],
      ),
    );
  }

  /// 构建答案按钮
  Widget _buildAnswerButton({
    required String label,
    required bool isVero,
  }) {
    // 判断按钮是否被用户选中
    final isSelected = widget.isAnswered && widget.userChoice == isVero;

    // 按钮背景色：如果已答题且被选中，变为蓝色；否则为白色
    final buttonColor = isSelected
        ? AppTheme.primary // 蓝色激活态
        : Colors.white; // 白色初始态

    // 文字颜色：如果已答题且被选中，变为白色；否则为深灰色
    final textColor = isSelected ? Colors.white : AppTheme.ink;

    return GestureDetector(
      onTap: widget.isAnswered ? null : () => widget.onAnswerSelected(isVero),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        height: 70, // 固定高度
        decoration: BoxDecoration(
          color: buttonColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
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
    );
  }

  /// 构建反馈标签（Badge）
  Widget _buildFeedbackBadge() {
    if (!widget.isAnswered || widget.isCorrect == null) {
      return const SizedBox.shrink();
    }

    // 使用 TweenAnimationBuilder 实现流畅的入场动画
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic, // 流畅的缓动曲线
      builder: (context, value, child) {
        return Opacity(
          opacity: value, // 淡入效果
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - value)), // 从下往上滑入（30px距离）
            child: Transform.scale(
              scale: 0.8 + (0.2 * value), // 从0.8缩放到1.0，增加弹性感
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: widget.isCorrect!
                      ? const Color(0xFF4ADE80) // 正确：绿色
                      : const Color(0xFFFF5252), // 错误：红色
                  borderRadius: BorderRadius.circular(20), // 胶囊型
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15 * value), // 阴影也跟随动画
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
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.isCorrect!
                              ? AppStrings.getWithLanguage(
                                  widget.currentLanguage, 'correct')
                              : AppStrings.getWithLanguage(
                                  widget.currentLanguage, 'wrong'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    // 错题已彻底消灭提示
                    if (widget.isCorrect! && widget.mistakeEliminated) ...[
                      const SizedBox(height: 4),
                      Text(
                        AppStrings.getWithLanguage(widget.currentLanguage,
                            'mistake_cleared_celebration'),
                        style: const TextStyle(
                          color: Colors.white,
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

  /// 构建收藏气泡（Badge）
  Widget _buildFavoriteBadge() {
    // 使用 TweenAnimationBuilder 实现流畅的入场动画
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
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
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
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
                    const Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppStrings.getWithLanguage(
                          widget.currentLanguage, 'favorited'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
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
    // 使用 TweenAnimationBuilder 实现流畅的入场动画
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
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
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
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
                    const Icon(
                      Icons.star,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppStrings.getWithLanguage(
                          widget.currentLanguage, 'mastered_badge_short'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
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
}
