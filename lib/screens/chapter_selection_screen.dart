import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/chapter_config.dart';
import '../models/chapter.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../providers/user_state_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/road_segmented_tabs.dart';
import 'practice_screen.dart';
import 'subscription_page.dart';

/// 章节选择页面
/// 参考 Stitch 设计稿，实现主要章节和次要章节的 Tab 切换
class ChapterSelectionScreen extends StatefulWidget {
  const ChapterSelectionScreen({super.key, this.focusChapterId});

  /// 從首頁學習路線進入時要定位並高亮的章節。
  final int? focusChapterId;

  @override
  State<ChapterSelectionScreen> createState() => _ChapterSelectionScreenState();
}

class _ChapterSelectionScreenState extends State<ChapterSelectionScreen> {
  int _selectedTab = 0; // 0: 主要章节, 1: 次要章节
  final _focusKey = GlobalKey();
  bool _focusScrolled = false;

  @override
  void initState() {
    super.initState();
    final focus = widget.focusChapterId;
    if (focus != null &&
        ChapterConfig.secondaryChapters.any((c) => c.id == focus)) {
      _selectedTab = 1;
    }
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
      builder: (dialogContext) {
        final warningColor = AppTheme.warningTextFor(dialogContext);
        final primaryColor = AppTheme.primaryFor(dialogContext);
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lock, color: warningColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
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
              child: Text(
                AppStrings.getWithLanguage(currentLang, 'nav_back'),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Theme.of(dialogContext).colorScheme.onPrimary,
              ),
              child: Text(
                AppStrings.getWithLanguage(
                  currentLang,
                  'go_subscribe_unlock',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLanguage =
        Provider.of<UserStateProvider>(context).currentLanguage;
    final principalChapters = ChapterConfig.principalChapters;
    final secondaryChapters = ChapterConfig.secondaryChapters;

    return Scaffold(
      // 頁面底色由主題提供，內容較短時也不會露出黑色窗口底。
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: AppTheme.pageDecorationFor(context),
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
    final colorScheme = Theme.of(context).colorScheme;
    final isRoad = AppTheme.usesRoadPalette && !AppTheme.isRetroFor(context);
    return Container(
      decoration: BoxDecoration(
        color: isRoad
            ? AppTheme.headerBackgroundFor(context)
            : colorScheme.surface.withOpacity(0.6),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withOpacity(0.2),
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
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(Icons.chevron_left, size: 28),
                  color: colorScheme.primary,
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),

                // 标题
                Expanded(
                  child: Text(
                    AppStrings.get('select_chapter'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
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
    if (AppTheme.usesRoadPalette && !AppTheme.isRetroFor(context)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: RoadSegmentedTabs(
          labels: [
            AppStrings.getWithLanguage(currentLanguage, 'principal_chapters'),
            AppStrings.getWithLanguage(currentLanguage, 'secondary_chapters'),
          ],
          selectedIndex: _selectedTab,
          onSelected: (index) => setState(() => _selectedTab = index),
        ),
      );
    }
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
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final primaryColor = AppTheme.primaryFor(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: isRetro ? BorderRadius.zero : BorderRadius.circular(20),
          color: isActive
              ? colorScheme.surface.withOpacity(0.9)
              : colorScheme.surface.withOpacity(0.45),
          border: Border.all(
            color: isActive
                ? primaryColor.withOpacity(isRetro ? 1 : 0.3)
                : Colors.transparent,
            width: 1,
          ),
          boxShadow: isRetro
              ? const []
              : isActive
                  ? [
                      BoxShadow(
                        color: primaryColor.withOpacity(0.1),
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
          borderRadius: isRetro ? BorderRadius.zero : BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: isRetro ? 0 : 20,
              sigmaY: isRetro ? 0 : 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    color: isActive
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive ? colorScheme.primary : Colors.transparent,
                    shape: isRetro ? BoxShape.rectangle : BoxShape.circle,
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
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // 章節數量有限（最多 15 個），一次建好才能把路線點進來的章節滾到可見處。
    final focusId = widget.focusChapterId;
    if (!_focusScrolled && chapters.any((c) => c.id == focusId)) {
      _focusScrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _focusKey.currentContext;
        if (!mounted || target == null) return;
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          alignment: 0.1,
        );
      });
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final chapter in chapters)
            Padding(
              key: chapter.id == focusId ? _focusKey : null,
              padding: const EdgeInsets.only(bottom: 16),
              child: _wrapFocus(
                context,
                isFocus: chapter.id == focusId,
                child: _buildChapterCard(
                  context,
                  chapter,
                  currentLanguage,
                  progress: chaptersProgress[chapter.id] ??
                      {
                        'total': 0,
                        'practiced': 0,
                        'mastered': 0,
                      },
                  isLocked: userStateProvider.isChapterLocked(chapter.id),
                  onTap: () => _navigateToPractice(chapter.id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 路線點進來的章節：外加一圈標誌黃描邊，與首頁「你在這裡」呼應。
  Widget _wrapFocus(
    BuildContext context, {
    required bool isFocus,
    required Widget child,
  }) {
    if (!isFocus) return child;
    final isRetro = AppTheme.isRetroFor(context);
    return Container(
      key: const Key('chapter_focus_highlight'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.accentFor(context),
        borderRadius:
            isRetro ? BorderRadius.zero : BorderRadius.circular(23),
      ),
      child: child,
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
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final primaryColor = AppTheme.primaryFor(context);
    final successColor = AppTheme.successFor(context);
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
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chapter.getTitle(currentLanguage),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
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
                          color: AppTheme.warningFor(context).withOpacity(0.16),
                          borderRadius: isRetro
                              ? BorderRadius.zero
                              : BorderRadius.circular(999),
                          border: Border.all(
                            color: AppTheme.warningTextFor(context)
                                .withOpacity(0.55),
                          ),
                        ),
                        child: Icon(
                          Icons.lock,
                          size: 14,
                          color: AppTheme.warningTextFor(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      AppStrings.getWithLanguage(
                              currentLanguage, 'chapter_stat_bank')
                          .replaceAll('{count}', '$total'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.getWithLanguage(
                              currentLanguage, 'chapter_stat_covered')
                          .replaceAll('{count}', '$practiced'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.getWithLanguage(
                              currentLanguage, 'chapter_stat_mastered')
                          .replaceAll('{count}', '$mastered'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
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
                          ? successColor
                          : (coveragePercentage > 0
                              ? primaryColor
                              : colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    '${coveragePercentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isCompleted
                          ? successColor
                          : (coveragePercentage > 0
                              ? primaryColor
                              : colorScheme.onSurfaceVariant),
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
                  color: colorScheme.onSurface.withOpacity(0.12),
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(3),
                ),
                child: ClipRRect(
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      // 进度条填充
                      FractionallySizedBox(
                        widthFactor: coveragePercentage / 100,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isCompleted ? successColor : primaryColor,
                            borderRadius: isRetro
                                ? BorderRadius.zero
                                : BorderRadius.circular(3),
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
