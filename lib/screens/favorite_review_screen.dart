import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/question.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../widgets/question_widget.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/translation_panel.dart';
import '../providers/user_state_provider.dart';

/// 收藏題目回顧頁面（僅列表，與錯題回顧一致的左中右三欄卡片佈局）
/// UI 與錯題回顧列表模式完全一致：左題號+綠圈、中題目+圖片、右下愛心/書本/翻譯
class FavoriteReviewScreen extends StatefulWidget {
  const FavoriteReviewScreen({super.key});

  @override
  State<FavoriteReviewScreen> createState() => _FavoriteReviewScreenState();
}

class _FavoriteReviewScreenState extends State<FavoriteReviewScreen> {
  List<Question> _favoriteQuestions = [];
  bool _isLoading = true;

  final Map<String, bool> _showTranslation = {};

  String get _currentLanguage =>
      Provider.of<UserStateProvider>(context, listen: false).currentLanguage;

  @override
  void initState() {
    super.initState();
    _loadFavoriteQuestions();
  }

  Future<void> _loadFavoriteQuestions() async {
    setState(() => _isLoading = true);

    try {
      final userStateProvider =
          Provider.of<UserStateProvider>(context, listen: false);
      final favoriteIds = await DatabaseService.getFavoriteQuestionIds(
        userId: userStateProvider.effectiveUserId,
      );

      if (favoriteIds.isEmpty) {
        setState(() {
          _favoriteQuestions = [];
          _isLoading = false;
        });
        return;
      }

      final questions = <Question>[];
      for (final id in favoriteIds) {
        final question = await DatabaseService.getQuestionById(id, lang: 'it');
        if (question != null) {
          if (_currentLanguage != 'it') {
            final translated = await DatabaseService.getQuestionById(id,
                lang: _currentLanguage);
            if (translated != null) {
              questions.add(question.mergeLanguages(translated));
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
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.get('failed_to_load')}: $e')),
        );
      }
    }
  }

  void _toggleTranslation(String questionId) {
    setState(() {
      _showTranslation[questionId] = !(_showTranslation[questionId] ?? false);
    });
  }

  /// 取消收藏並從列表中移除
  Future<void> _unfavoriteAndRemove(String questionId) async {
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    final wasFavorite = await DatabaseService.isFavorite(
      questionId,
      userId: userStateProvider.effectiveUserId,
    );
    if (!wasFavorite) return;

    await DatabaseService.toggleFavorite(
      questionId,
      userId: userStateProvider.effectiveUserId,
    );
    if (mounted) {
      setState(() {
        _favoriteQuestions.removeWhere((q) => q.id == questionId);
      });
    }
  }

  /// 打開結構化解析彈窗（所有用戶免費不限次）
  Future<void> _openExplanationModal(Question question) async {
    await QuestionWidget.showRichExplanation(
      context,
      question: question,
      currentLanguage: _currentLanguage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          AppStrings.get('favorite_questions'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        decoration: AppTheme.pageDecorationFor(context),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _favoriteQuestions.isEmpty
                ? _buildEmptyFavoritesState(context)
                : _buildFavoriteList(),
      ),
    );
  }

  Widget _buildEmptyFavoritesState(BuildContext context) {
    final isRetro = AppTheme.isRetroFor(context);
    return EmptyStateView(
      icon: Icons.favorite_border_rounded,
      title: AppStrings.get('empty_favorites_title'),
      description: AppStrings.get('empty_favorites_description'),
      action: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryFor(context),
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius:
                isRetro ? BorderRadius.zero : BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
        onPressed: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        child: Text(
          AppStrings.get('go_practice_now'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildFavoriteList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      itemCount: _favoriteQuestions.length,
      itemBuilder: (context, index) {
        final question = _favoriteQuestions[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildFavoriteCard(question, index),
        );
      },
    );
  }

  /// 單張收藏卡片（與錯題 _buildQuestionCard 一致，左題號+綠圈無錯誤次數、中內容、右下三圖標）
  Widget _buildFavoriteCard(Question question, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final cardRadius =
        isRetro ? BorderRadius.zero : BorderRadius.circular(AppTheme.radiusXl);
    final questionId = question.id;
    final correctAnswer = question.answer;
    final questionText = question.getDisplayQuestionText(
      defaultText: AppStrings.get('question_content_missing'),
    );
    final translationText = question.getQuestionText(_currentLanguage);
    final hasImage =
        question.imageName != null && question.imageName!.isNotEmpty;

    return ClipRRect(
      borderRadius: cardRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: isRetro ? 0 : 20,
          sigmaY: isRetro ? 0 : 20,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceFor(context),
            borderRadius: cardRadius,
            border: Border.all(
              color: AppTheme.lineFor(context).withOpacity(0.72),
            ),
            boxShadow: AppTheme.cardShadowFor(context),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLeftGutter(index, correctAnswer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: hasImage
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      Text(
                        questionText,
                        // 意大利语题干始终从左到右排版（包括乌尔都语界面）。
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (hasImage) ...[
                        const SizedBox(height: 12),
                        _buildQuestionImage(question.imageName!),
                      ],
                      if (_showTranslation[questionId] == true &&
                          translationText != null) ...[
                        const SizedBox(height: 16),
                        TranslationPanel(
                          text: translationText,
                          languageCode: _currentLanguage,
                        ),
                      ],
                      if (_showTranslation[questionId] == true) ...[
                        const SizedBox(height: 8),
                        _buildKeyWordsChips(question),
                      ],
                      const SizedBox(height: 16),
                      _buildBottomActions(question),
                      const SizedBox(height: 4),
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

  /// 左欄：題號 + 正確答案綠圈（收藏頁不顯示「錯誤 X 次」）
  Widget _buildLeftGutter(int index, bool correctAnswer) {
    final label = correctAnswer ? 'V' : 'F';
    final isRetro = AppTheme.isRetroFor(context);
    return SizedBox(
      width: 46,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: isRetro ? 11 : 10,
                fontWeight: FontWeight.w500,
                color: AppTheme.mutedFor(context),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _buildAnswerCircle(label: label),
        ],
      ),
    );
  }

  Widget _buildAnswerCircle({required String label}) {
    final isRetro = AppTheme.isRetroFor(context);
    final successColor = AppTheme.successFor(context);
    return SizedBox(
      width: 32,
      height: 32,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: isRetro ? BoxShape.rectangle : BoxShape.circle,
          color: AppTheme.successSoftFor(context),
          border: Border.all(
            color: successColor,
            width: 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: successColor,
            ),
          ),
        ),
      ),
    );
  }

  /// 右下角：愛心（取消收藏並移除）、書本（彈出解析）、翻譯（展開/收起）
  Widget _buildBottomActions(Question question) {
    final questionId = question.id;
    final isTranslationActive = _showTranslation[questionId] == true;
    final primaryColor = AppTheme.primaryFor(context);
    final mutedColor = AppTheme.mutedFor(context);
    final isItalian = _currentLanguage == 'it';

    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildActionButton(
            tooltip: AppStrings.get('unfavorite'),
            icon: Icons.favorite,
            color: AppTheme.dangerFor(context),
            onPressed: () => _unfavoriteAndRemove(questionId),
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            tooltip: AppStrings.get('btn_explanation'),
            icon: Icons.menu_book_outlined,
            color: mutedColor,
            onPressed: () async {
              await _openExplanationModal(question);
            },
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            tooltip: AppStrings.get('translation'),
            icon: Icons.translate,
            color: isItalian
                ? mutedColor.withOpacity(0.45)
                : isTranslationActive
                    ? primaryColor
                    : mutedColor,
            isActive: isTranslationActive,
            onPressed: isItalian ? null : () => _toggleTranslation(questionId),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool isActive = false,
  }) {
    final isRetro = AppTheme.isRetroFor(context);
    final primaryColor = AppTheme.primaryFor(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 19, color: color),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(44),
        backgroundColor: isActive
            ? AppTheme.primarySoftFor(context)
            : AppTheme.surfaceFor(context),
        shape: isRetro
            ? const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              )
            : const CircleBorder(),
        side: isRetro
            ? const BorderSide(color: AppTheme.retroLine)
            : BorderSide(color: primaryColor.withOpacity(isActive ? 0.3 : 0.1)),
      ),
    );
  }

  Widget _buildQuestionImage(String imagePath) {
    final isRetro = AppTheme.isRetroFor(context);
    return GestureDetector(
      onTap: () => _showImagePreview(imagePath),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          ClipRRect(
            borderRadius:
                isRetro ? BorderRadius.zero : BorderRadius.circular(12),
            child: _buildImageWidget(imagePath),
          ),
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(3.4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius:
                    isRetro ? BorderRadius.zero : BorderRadius.circular(5.1),
                border: Border.all(
                  color: Colors.white.withOpacity(0.9),
                  width: 1.0,
                ),
              ),
              child: const Icon(
                Icons.search,
                size: 12,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWidget(String imagePath) {
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        height: 100,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    String assetPath = imagePath;
    if (assetPath.startsWith('/')) assetPath = assetPath.substring(1);
    if (assetPath.startsWith('img_sign/')) assetPath = 'images/$assetPath';
    return Image.asset(
      assetPath,
      height: 100,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  void _showImagePreview(String imagePath) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      barrierDismissible: true,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: _buildLargeImage(imagePath),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLargeImage(String imagePath) {
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildImageErrorPlaceholder(),
      );
    }
    String assetPath = imagePath;
    if (assetPath.startsWith('/')) assetPath = assetPath.substring(1);
    if (assetPath.startsWith('img_sign/')) assetPath = 'images/$assetPath';
    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _buildImageErrorPlaceholder(),
    );
  }

  Widget _buildImageErrorPlaceholder() {
    final isRetro = AppTheme.isRetroFor(context);
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppTheme.surfaceFor(context),
        borderRadius: isRetro ? BorderRadius.zero : BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lineFor(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported,
            size: 64,
            color: AppTheme.mutedFor(context),
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.get('failed_to_load'),
            style: TextStyle(color: AppTheme.mutedFor(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyWordsChips(Question question) {
    final keywords = question.getKeyWords(_currentLanguage);
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    if (keywords.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: keywords.map((keyword) {
          final itWord = keyword['it'] ?? '';
          final translation =
              keyword[_currentLanguage] ?? keyword['en'] ?? keyword['zh'] ?? '';

          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceFor(context),
                borderRadius:
                    isRetro ? BorderRadius.zero : BorderRadius.circular(12),
                border: Border.all(color: AppTheme.lineFor(context)),
              ),
              child: Wrap(
                spacing: 5,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    itWord,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (translation.isNotEmpty) ...[
                    Text(
                      '•',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      translation,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
