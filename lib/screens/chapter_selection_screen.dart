import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/chapter_config.dart';
import '../models/chapter.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../providers/user_state_provider.dart';
import '../widgets/glass_card.dart';
import 'practice_screen.dart';
import 'subscription_page.dart';

/// 章节选择页面
/// 参考 Stitch 设计稿，实现主要章节和次要章节的 Tab 切换
class ChapterSelectionScreen extends StatefulWidget {
  const ChapterSelectionScreen({super.key});

  @override
  State<ChapterSelectionScreen> createState() => _ChapterSelectionScreenState();
}

class _ChapterSelectionScreenState extends State<ChapterSelectionScreen> {
  int _selectedTab = 0; // 0: 主要章节, 1: 次要章节

  @override
  void initState() {
    super.initState();
    // 如果 Provider 中还没有缓存，则触发加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userStateProvider =
          Provider.of<UserStateProvider>(context, listen: false);
      if (userStateProvider.chaptersProgressCache == null) {
        userStateProvider.refreshChaptersProgress();
      }
    });
  }

  /// 导航到练习页面（先检查章节锁和每日额度，超额则弹订阅引导）
  Future<void> _navigateToPractice(int chapterId) async {
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    await userStateProvider.checkAndResetDailyCounters();
    if (!mounted) return;

    if (userStateProvider.isChapterLocked(chapterId)) {
      final currentLang = userStateProvider.currentLanguage;
      final result = await _showVipPromptDialog(
        title: AppStrings.getWithLanguage(currentLang, 'chapter_locked_title'),
        message:
            AppStrings.getWithLanguage(currentLang, 'chapter_locked_message'),
        currentLang: currentLang,
      );
      if (!mounted) return;
      if (result == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SubscriptionPage(),
          ),
        );
      }
      return;
    }

    if (!userStateProvider.canPractice()) {
      final currentLang = userStateProvider.currentLanguage;
      final result = await _showVipPromptDialog(
        title: AppStrings.getWithLanguage(currentLang, 'quiz_limit_reached'),
        message: AppStrings.getWithLanguage(currentLang, 'quiz_limit_message'),
        currentLang: currentLang,
      );
      if (!mounted) return;
      if (result == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SubscriptionPage(),
          ),
        );
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PracticeScreen(
          chapterId: chapterId,
          skipMastered: userStateProvider.skipMastered,
        ),
      ),
    ).then((_) => userStateProvider.syncProgressToCloudIfVip());
  }

  Future<bool?> _showVipPromptDialog({
    required String title,
    required String message,
    required String currentLang,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.lock, color: Colors.amber, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.getWithLanguage(currentLang, 'nav_back')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
            child: Text(
              AppStrings.getWithLanguage(currentLang, 'go_subscribe_unlock'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLanguage =
        Provider.of<UserStateProvider>(context).currentLanguage;
    final principalChapters = ChapterConfig.principalChapters;
    final secondaryChapters = ChapterConfig.secondaryChapters;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: AppTheme.pageDecoration,
        child: SafeArea(
          child: Column(
            children: [
              // 顶部 Header（玻璃态效果）
              _buildHeader(context),

              // Tab 切换按钮
              _buildTabSwitcher(context, currentLanguage),

              // 章节列表
              Expanded(
                child: Consumer<UserStateProvider>(
                  builder: (context, userStateProvider, child) {
                    final chaptersProgress =
                        userStateProvider.chaptersProgressCache;

                    if (chaptersProgress == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return _buildChapterList(
                      context,
                      _selectedTab == 0 ? principalChapters : secondaryChapters,
                      currentLanguage,
                      chaptersProgress: chaptersProgress,
                      userStateProvider: userStateProvider,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建顶部 Header
  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withOpacity(0.05),
            width: 0.5,
          ),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 返回按钮
                IconButton(
                  icon: const Icon(Icons.chevron_left,
                      size: 28, color: AppTheme.primary),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),

                // 标题
                Expanded(
                  child: Text(
                    AppStrings.get('select_chapter'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.ink,
                      letterSpacing: 0,
                    ),
                  ),
                ),

                // 占位，保持标题居中
                const SizedBox(width: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建 Tab 切换按钮
  Widget _buildTabSwitcher(BuildContext context, String currentLanguage) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 主要章节 Tab
          Expanded(
            child: _buildTabButton(
              context,
              title: AppStrings.getWithLanguage(
                  currentLanguage, 'principal_chapters'),
              isActive: _selectedTab == 0,
              onTap: () {
                setState(() {
                  _selectedTab = 0;
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          // 次要章节 Tab
          Expanded(
            child: _buildTabButton(
              context,
              title: AppStrings.getWithLanguage(
                  currentLanguage, 'secondary_chapters'),
              isActive: _selectedTab == 1,
              onTap: () {
                setState(() {
                  _selectedTab = 1;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单个 Tab 按钮
  Widget _buildTabButton(
    BuildContext context, {
    required String title,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isActive
              ? Colors.white.withOpacity(0.85)
              : Colors.white.withOpacity(0.45),
          border: Border.all(
            color: isActive
                ? AppTheme.primary.withOpacity(0.3)
                : Colors.transparent,
            width: 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [
                  BoxShadow(
                    color: const Color(0xFF1F2687).withOpacity(0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    color: isActive ? AppTheme.primary : AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive ? AppTheme.primary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建章节列表
  Widget _buildChapterList(
    BuildContext context,
    List<ChapterModel> chapters,
    String currentLanguage, {
    required Map<int, Map<String, int>> chaptersProgress,
    required UserStateProvider userStateProvider,
  }) {
    if (chapters.isEmpty) {
      return Center(
        child: Text(
          AppStrings.get('no_chapters'),
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final progress = chaptersProgress[chapter.id] ??
            {
              'total': 0,
              'practiced': 0,
              'mastered': 0,
            };
        final isLocked = userStateProvider.isChapterLocked(chapter.id);

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildChapterCard(
            context,
            chapter,
            currentLanguage,
            progress: progress,
            isLocked: isLocked,
            onTap: () => _navigateToPractice(chapter.id),
          ),
        );
      },
    );
  }

  /// 构建章节卡片
  Widget _buildChapterCard(
    BuildContext context,
    ChapterModel chapter,
    String currentLanguage, {
    required Map<String, int> progress,
    required bool isLocked,
    required VoidCallback onTap,
  }) {
    final total = progress['total'] ?? 0;
    final practiced = progress['practiced'] ?? 0;
    final mastered = progress['mastered'] ?? 0;
    final coveragePercentage = total > 0 ? (practiced / total * 100) : 0.0;
    final isCompleted = coveragePercentage >= 100.0;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 章节标题和统计数据
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：章节标题
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${chapter.id}. ${chapter.titleIt}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.ink,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chapter.getTitle(currentLanguage),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),

              // 右侧：统计数据
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isLocked) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.amber.withOpacity(0.55),
                          ),
                        ),
                        child: const Icon(
                          Icons.lock,
                          size: 14,
                          color: Color(0xFFD97706),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      AppStrings.getWithLanguage(
                              currentLanguage, 'chapter_stat_bank')
                          .replaceAll('{count}', '$total'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.getWithLanguage(
                              currentLanguage, 'chapter_stat_covered')
                          .replaceAll('{count}', '$practiced'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.getWithLanguage(
                              currentLanguage, 'chapter_stat_mastered')
                          .replaceAll('{count}', '$mastered'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 进度条
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppStrings.getWithLanguage(
                        currentLanguage, 'study_progress'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isCompleted
                          ? const Color(0xFF4CAF50)
                          : (coveragePercentage > 0
                              ? AppTheme.primary
                              : const Color(0xFF94a3b8)),
                    ),
                  ),
                  Text(
                    '${coveragePercentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isCompleted
                          ? const Color(0xFF4CAF50)
                          : (coveragePercentage > 0
                              ? AppTheme.primary
                              : const Color(0xFF94a3b8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 进度条背景
              Container(
                width: double.infinity,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFFcfd9e7).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      // 进度条填充
                      FractionallySizedBox(
                        widthFactor: coveragePercentage / 100,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? const Color(0xFF4CAF50) // 亮绿色
                                : AppTheme.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
