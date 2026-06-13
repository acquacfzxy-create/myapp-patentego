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
import 'subscription_page.dart';

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

  /// 打開結構化解析彈窗（與練習模式一致的限額檢查與計次）
  Future<void> _openExplanationModal(Question question) async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageMid,
      appBar: AppBar(
        title: Text(
          AppStrings.get('favorite_questions'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: Color(0xFF475569),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        decoration: AppTheme.pageDecoration,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _favoriteQuestions.isEmpty
                ? _buildEmptyFavoritesState(context)
                : _buildFavoriteList(),
      ),
    );
  }

  Widget _buildEmptyFavoritesState(BuildContext context) {
    return EmptyStateView(
      icon: Icons.favorite_border_rounded,
      title: AppStrings.get('empty_favorites_title'),
      description: AppStrings.get('empty_favorites_description'),
      action: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
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
    final questionId = question.id;
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                          color: Color(0xFF0D131B),
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
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: Colors.grey[500],
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
    return SizedBox(
      width: 28,
      height: 28,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.green.withOpacity(0.1),
          border: Border.all(
            color: Colors.green[300]!,
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
              color: Colors.green[700]!,
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

    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _unfavoriteAndRemove(questionId),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey[100]!.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.favorite,
                size: 16,
                color: Colors.red[400],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () async {
              await _openExplanationModal(question);
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey[100]!.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.menu_book_outlined,
                size: 16,
                color: Colors.grey[400],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _currentLanguage == 'it'
                ? null
                : () => _toggleTranslation(questionId),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey[100]!.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.translate,
                size: 16,
                color: _currentLanguage == 'it'
                    ? Colors.grey[300]
                    : (isTranslationActive
                        ? const Color(0xFF137FEC)
                        : Colors.grey[400]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionImage(String imagePath) {
    return GestureDetector(
      onTap: () => _showImagePreview(imagePath),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildImageWidget(imagePath),
          ),
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(3.4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(5.1),
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
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_not_supported, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            AppStrings.get('failed_to_load'),
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyWordsChips(Question question) {
    final keywords = question.getKeyWords(_currentLanguage);
    if (keywords.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: keywords.map((keyword) {
        final itWord = keyword['it'] ?? '';
        final translation =
            keyword[_currentLanguage] ?? keyword['en'] ?? keyword['zh'] ?? '';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                itWord,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              if (translation.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text('•',
                    style: TextStyle(fontSize: 9, color: Colors.grey[400])),
                const SizedBox(width: 4),
                Text(
                  translation,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
