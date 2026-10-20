import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'practice_screen.dart';
import 'mock_test_screen.dart';
import 'settings_screen.dart';
import 'mistake_review_screen.dart';
import 'favorite_review_screen.dart';
import 'chapter_selection_screen.dart';
import 'subscription_page.dart';
import 'mastery_report_screen.dart';
import '../services/database_service.dart';
import '../services/access_policy.dart';
import '../services/firebase_status.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../config/chapter_config.dart';
import '../config/route_observer.dart';
import '../providers/user_state_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/circular_progress_card.dart';
import '../widgets/learning_route_card.dart';
import '../widgets/road_sign_icon.dart';

/// 首頁
/// 提供應用的主要功能入口
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// 系统字级放大到辅助功能级别（iOS Larger Accessibility Sizes）时返回 true，
/// 用于把横排小组件改成竖排，避免文字被挤成单字断行或截断。
bool _isLargeTextScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;

class _DailyPlanProgressRow extends StatelessWidget {
  const _DailyPlanProgressRow({
    required this.icon,
    required this.label,
    required this.completed,
    required this.goal,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int completed;
  final int goal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hasGoal = goal > 0;
    final progress = hasGoal
        ? (completed / goal).clamp(0.0, 1.0)
        : completed > 0
            ? 1.0
            : 0.0;
    final progressLabel = hasGoal ? '$completed / $goal' : '$completed';
    final isRetro = AppTheme.isRetroFor(context);
    if (_isLargeTextScale(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                progressLabel,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius:
                isRetro ? BorderRadius.zero : BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 7),
        SizedBox(
          width: 80,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: ClipRRect(
            borderRadius:
                isRetro ? BorderRadius.zero : BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            progressLabel,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeScreenState extends State<HomeScreen>
    with RouteAware, TickerProviderStateMixin {
  // 動畫控制器
  late AnimationController _coverageAnimationController;
  late AnimationController _masteryAnimationController;
  late Animation<double> _coverageAnimation;
  late Animation<double> _masteryAnimation;
  int? _recommendedWeakChapterId;
  Map<int, Map<String, int>> _chapterProgress = const {};

  // 獲取當前語言
  String get _currentLanguage {
    try {
      return Provider.of<UserStateProvider>(context, listen: false)
          .currentLanguage;
    } catch (e) {
      return 'zh'; // 默認值
    }
  }

  @override
  void initState() {
    super.initState();

    // 初始化動畫控制器
    _coverageAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _masteryAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _coverageAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _coverageAnimationController, curve: Curves.easeOut),
    );
    _masteryAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _masteryAnimationController, curve: Curves.easeOut),
    );

    _checkDatabaseStatus();
    _loadStatistics();
    // 初始化掌握度统计
    _initMasteryStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 订阅路由观察者
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    // 取消订阅路由观察者
    routeObserver.unsubscribe(this);
    // 釋放動畫控制器
    _coverageAnimationController.dispose();
    _masteryAnimationController.dispose();
    super.dispose();
  }

  /// 当从其他页面返回到当前页面时调用
  @override
  void didPopNext() {
    // 从其他页面返回首页时，更新掌握度统计
    if (mounted) {
      final userStateProvider =
          Provider.of<UserStateProvider>(context, listen: false);
      userStateProvider.checkAndResetDailyCounters().then((_) async {
        if (!mounted) return;
        await _loadStatistics();
      }).catchError((e) {
        // 忽略错误，不阻塞UI
      });
    }
  }

  /// 初始化掌握度统计
  Future<void> _initMasteryStats() async {
    // 确保 Provider 已经初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final userStateProvider =
            Provider.of<UserStateProvider>(context, listen: false);
        userStateProvider.updateMasteryStats().catchError((e) {
          // 忽略错误，不阻塞UI
        });
      }
    });
  }

  /// 檢查數據庫狀態，如果未初始化則嘗試初始化
  Future<void> _checkDatabaseStatus() async {
    if (!DatabaseService.isInitialized && DatabaseService.initError == null) {
      try {
        await DatabaseService.init();
        if (mounted) {
          setState(() {});
          _loadStatistics();
        }
      } catch (e) {
        if (mounted) {
          setState(() {});
        }
      }
    } else if (DatabaseService.isInitialized) {
      if (mounted) {
        setState(() {});
        _loadStatistics();
      }
    }
  }

  /// 加載統計信息（已簡化，統計數據由 UserStateProvider 管理）
  Future<void> _loadStatistics() async {
    if (!DatabaseService.isInitialized) return;

    try {
      // 觸發 UserStateProvider 更新統計數據
      final userStateProvider =
          Provider.of<UserStateProvider>(context, listen: false);
      await userStateProvider.checkAndResetDailyCounters();
      await Future.wait([
        userStateProvider.updateMasteryStats(),
        userStateProvider.refreshMistakeCount(),
        userStateProvider.refreshDailyPlanProgress(),
        userStateProvider.refreshDueReviewCount(),
        userStateProvider.refreshLearningStreak(),
      ]);
      final weakChaptersFuture = DatabaseService.getTopWeakChapters(
        userId: userStateProvider.effectiveUserId,
        limit: 3,
      );
      final chapterProgressFuture = DatabaseService.getChaptersProgress(
        ChapterConfig.chapters.map((chapter) => chapter.id).toList(),
        userId: userStateProvider.effectiveUserId,
      );
      final weakChapters = await weakChaptersFuture;
      final chapterProgress = await chapterProgressFuture;
      int? recommendedWeakChapter;
      for (final entry in weakChapters) {
        final chapterId = entry['chapter'];
        if (chapterId != null &&
            !userStateProvider.isChapterLocked(chapterId)) {
          recommendedWeakChapter = chapterId;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _recommendedWeakChapterId = recommendedWeakChapter;
          _chapterProgress = chapterProgress;
        });
      }
    } catch (e) {
      // 忽略錯誤，不阻塞UI
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用Consumer监听UserStateProvider的变化，确保语言切换时UI更新
    return Consumer<UserStateProvider>(
      builder: (context, userStateProvider, child) {
        final dbError = DatabaseService.initError;
        final isDbReady = DatabaseService.isInitialized;

        return _buildHomeContent(
            context, dbError, isDbReady, userStateProvider);
      },
    );
  }

  Widget _buildHomeContent(BuildContext context, String? dbError,
      bool isDbReady, UserStateProvider userStateProvider) {
    // 顯示數據庫錯誤提示
    if (dbError != null && !isDbReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${AppStrings.get('database_init_failed')}\n${AppStrings.get('errors')}: $dbError'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: AppStrings.get('retry'),
              textColor: Colors.white,
              onPressed: () async {
                try {
                  DatabaseService.initError = null;
                  await DatabaseService.init();
                  if (mounted) {
                    setState(() {});
                    _loadStatistics();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppStrings.get('database_init_success')),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    setState(() {});
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${AppStrings.get('retry_failed')}: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ),
        );
      });
    }

    return Scaffold(
      body: Container(
        decoration: AppTheme.pageDecorationFor(context),
        child: RefreshIndicator(
          onRefresh: _loadStatistics,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 自定义头部
              SliverToBoxAdapter(
                child: _buildHeader(context),
              ),
              // 今日路程：首頁唯一主行動
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: _buildDailyGoalStrip(context, userStateProvider),
                ),
              ),
              // 學習路線
              if (isDbReady)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                    child: _buildLearningRoute(context, userStateProvider),
                  ),
                ),
              // 功能网格
              SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                sliver: SliverGrid(
                  // 大字级（如 iOS 辅助功能字级）时改为单列，并按字高给足卡片高度，
                  // 避免固定 1:1 比例的卡片内容溢出。
                  gridDelegate: MediaQuery.textScalerOf(context).scale(14) >
                          14 * 1.3
                      ? SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 1,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 18 * 2 +
                              56 +
                              10 +
                              8 +
                              2 *
                                  1.15 *
                                  MediaQuery.textScalerOf(context).scale(14),
                        )
                      : const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.0,
                        ),
                  delegate: SliverChildListDelegate([
                    _buildFeatureCard(
                      context,
                      title: AppStrings.get('random_practice'),
                      sign: RoadSignKind.freePractice,
                      icon: Icons.shuffle,
                      iconColor: AppTheme.primaryFor(context),
                      bgColor: AppTheme.primarySoftFor(context),
                      onTap: isDbReady
                          ? () async {
                              final userStateProvider =
                                  Provider.of<UserStateProvider>(context,
                                      listen: false);
                              await userStateProvider
                                  .checkAndResetDailyCounters();
                              if (!context.mounted) return;
                              if (!userStateProvider.canPractice()) {
                                final result = await _showSubscriptionDialog(
                                  context,
                                  AppStrings.getWithLanguage(
                                      _currentLanguage, 'quiz_limit_reached'),
                                  AppStrings.getWithLanguage(
                                      _currentLanguage, 'quiz_limit_message'),
                                );
                                if (!context.mounted) return;
                                if (result == true) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const SubscriptionPage(),
                                    ),
                                  );
                                }
                                return;
                              }
                              if (!context.mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PracticeScreen(
                                    skipMastered:
                                        userStateProvider.skipMastered,
                                  ),
                                ),
                              ).then((_) =>
                                  userStateProvider.syncProgressToCloudIfVip());
                            }
                          : null,
                    ),
                    _buildFeatureCard(
                      context,
                      title: AppStrings.get('chapter_practice'),
                      sign: RoadSignKind.chapters,
                      icon: Icons.menu_book,
                      iconColor: AppTheme.successFor(context),
                      bgColor: AppTheme.successSoftFor(context),
                      onTap: isDbReady
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ChapterSelectionScreen(),
                                ),
                              );
                            }
                          : null,
                    ),
                    _buildFeatureCard(
                      context,
                      title: AppStrings.get('official_mock_test'),
                      sign: RoadSignKind.mockTest,
                      icon: Icons.timer,
                      iconColor: AppTheme.warningTextFor(context),
                      bgColor: AppTheme.warningFor(context).withOpacity(0.12),
                      onTap: isDbReady
                          ? () {
                              _checkAndNavigateToMockTest(context);
                            }
                          : null,
                    ),
                    _buildFeatureCard(
                      context,
                      title: AppStrings.get('mistake_review'),
                      sign: RoadSignKind.mistakes,
                      icon: Icons.report,
                      iconColor: AppTheme.dangerFor(context),
                      bgColor: AppTheme.dangerSoftFor(context),
                      onTap: isDbReady
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const MistakeReviewScreen(),
                                ),
                              );
                            }
                          : null,
                    ),
                  ]),
                ),
              ),
              // 进度卡片
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: _buildProgressCard(context),
                ),
              ),
              // 收藏按钮
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: _buildFavoriteButton(context, isDbReady),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.viewPaddingOf(context).bottom + 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 構建頭部（用戶信息 + 設置按鈕）
  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);

    // 獲取用戶名稱（優先顯示名稱，否則顯示郵箱，最後顯示默認）
    String userName = 'User';
    final displayName = FirebaseStatus.currentUserDisplayName;
    final email = FirebaseStatus.currentUserEmail;
    if (displayName != null && displayName.isNotEmpty) {
      userName = displayName;
    } else if (email != null) {
      userName = email.split('@')[0];
    }

    final greeting = AppStrings.getWithLanguage(
      _currentLanguage,
      'home_greeting',
    );
    final greetingText =
        _currentLanguage == 'ur' ? greeting : '$greeting, $userName';

    // VIP 狀態文字
    final vipText = userStateProvider.isVip
        ? AppStrings.getWithLanguage(_currentLanguage, 'premium_user')
        : AppStrings.getWithLanguage(_currentLanguage, 'free_user');

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        child: Row(
          children: [
            // 用戶信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greetingText,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    vipText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: userStateProvider.isVip
                          ? AppTheme.primaryFor(context)
                          : colorScheme.onSurfaceVariant,
                      letterSpacing: 0.15,
                    ),
                  ),
                ],
              ),
            ),
            // 設置按鈕
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: isRetro ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: isRetro ? BorderRadius.zero : null,
                color: isRetro
                    ? AppTheme.retroPageAlt
                    : colorScheme.surface.withOpacity(0.4),
                border: Border.all(
                  color: isRetro
                      ? AppTheme.retroLine
                      : colorScheme.onSurface.withOpacity(0.12),
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(22),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );

                    if (mounted) {
                      setState(() {});
                      _loadStatistics();
                    }
                  },
                  child: Icon(
                    Icons.settings,
                    color: isRetro
                        ? AppTheme.retroInk
                        : colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 構建進度卡片（使用圓形進度條）
  Widget _buildProgressCard(BuildContext context) {
    const int totalQuestions = 7139;

    return Consumer<UserStateProvider>(
      builder: (context, userStateProvider, child) {
        final colorScheme = Theme.of(context).colorScheme;
        final isRetro = AppTheme.isRetroFor(context);
        final primaryColor = AppTheme.primaryFor(context);
        final masteredCount = userStateProvider.masteredCount;
        final attemptedCount = userStateProvider.attemptedCount;

        // 計算百分比
        final coveragePercentage = (attemptedCount / totalQuestions) * 100;
        final masteryPercentage = (masteredCount / totalQuestions) * 100;

        // 更新動畫目標值並啟動動畫
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _coverageAnimation = Tween<double>(
              begin: _coverageAnimation.value,
              end: coveragePercentage,
            ).animate(
              CurvedAnimation(
                parent: _coverageAnimationController,
                curve: Curves.easeOut,
              ),
            );
            _masteryAnimation = Tween<double>(
              begin: _masteryAnimation.value,
              end: masteryPercentage,
            ).animate(
              CurvedAnimation(
                parent: _masteryAnimationController,
                curve: Curves.easeOut,
              ),
            );
            _coverageAnimationController.forward(from: 0.0);
            _masteryAnimationController.forward(from: 0.0);
          }
        });

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MasteryReportScreen(),
              ),
            );
          },
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            borderRadius: BorderRadius.circular(24),
            onTap: null,
            enableScaleAnimation: false,
            child: Column(
              children: [
                // 標題 + 詳細分析入口
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 8,
                    children: [
                      Text(
                        AppStrings.get('study_progress').toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isRetro
                              ? AppTheme.retroPageAlt
                              : colorScheme.primary.withOpacity(0.1),
                          borderRadius: isRetro
                              ? BorderRadius.zero
                              : BorderRadius.circular(999),
                          border: Border.all(
                            color: isRetro
                                ? AppTheme.retroLine
                                : colorScheme.primary.withOpacity(0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                AppStrings.getWithLanguage(
                                    _currentLanguage, 'detailed_analysis'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 9,
                              color: primaryColor,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 圓形進度條
                AnimatedBuilder(
                  animation:
                      Listenable.merge([_coverageAnimation, _masteryAnimation]),
                  builder: (context, child) {
                    return CircularProgressCard(
                      coveragePercentage: _coverageAnimation.value,
                      masteryPercentage: _masteryAnimation.value,
                      attemptedCount: attemptedCount,
                      masteredCount: masteredCount,
                      questionUnit: _getQuestionText(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // 統計數據
                Container(
                  padding: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: colorScheme.outlineVariant.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  AppStrings.get('covered_questions')
                                      .toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '$attemptedCount ',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      TextSpan(
                                        text: _getQuestionText(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.normal,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 36,
                        color: colorScheme.outlineVariant.withOpacity(0.6),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  AppStrings.get('mastered_questions')
                                      .toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isRetro
                                        ? primaryColor
                                        : colorScheme.secondary,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '$masteredCount ',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      TextSpan(
                                        text: _getQuestionText(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.normal,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 道路主題下今日路程是綠色路牌卡：用局部 Theme 把卡內文字改成白色，
  /// 主按鈕改成標誌黃厚底按鈕；復古與 Web 保持原樣。
  Widget _buildDailyGoalStrip(
    BuildContext context,
    UserStateProvider userStateProvider,
  ) {
    final isRoadHero =
        AppTheme.usesRoadPalette && !AppTheme.isRetroFor(context);
    if (!isRoadHero) {
      return _buildDailyGoalStripBody(context, userStateProvider);
    }
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final heroTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: Colors.white,
        onSurface: Colors.white,
        onSurfaceVariant: Colors.white.withOpacity(0.86),
        surface: isDark ? AppTheme.roadNightPrimarySoft : AppTheme.roadPrimary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.roadAccent,
          foregroundColor: AppTheme.roadInk,
          // 額度用完：深綠實底，與可點的黃色按鈕明顯區分。
          disabledBackgroundColor:
              isDark ? Colors.black.withOpacity(0.35) : AppTheme.roadPrimaryDark,
          disabledForegroundColor: Colors.white.withOpacity(0.86),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.roadInk, width: 2),
          ),
          // 沿用主題字體（含多語言 fallback），只加粗加大。
          textStyle: theme.textTheme.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
    return Theme(
      data: heroTheme,
      child: Builder(
        builder: (heroContext) =>
            _buildDailyGoalStripBody(heroContext, userStateProvider),
      ),
    );
  }

  Widget _buildDailyGoalStripBody(
    BuildContext context,
    UserStateProvider userStateProvider,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final isRoadHero = AppTheme.usesRoadPalette && !isRetro;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 綠色路牌卡上，主色元素改用標誌黃，複習改用白色，保證對比度。
    final primaryColor =
        isRoadHero ? AppTheme.roadAccent : AppTheme.primaryFor(context);
    final reviewColor = isRetro
        ? primaryColor
        : isRoadHero
            ? Colors.white
            : const Color(0xFF7C3AED);
    final streakColor = isRetro
        ? primaryColor
        : isRoadHero
            ? AppTheme.roadAccent
            : const Color(0xFFF59E0B);
    final plan = userStateProvider.currentDailyPlan;
    // 今日新題與複習都已達標：主按鈕改為「再練一組」，直接進入今日建議。
    final planComplete =
        max(0, plan.newGoal - userStateProvider.dailyNewQuestionCount) +
                max(0,
                    plan.reviewGoal - userStateProvider.dailyReviewQuestionCount) ==
            0;
    final canPractice = userStateProvider.canPractice();
    final streak = userStateProvider.learningStreak;
    final estimatedText = plan.newGoal == 0
        ? AppStrings.getWithLanguage(_currentLanguage, 'daily_goal_all_done')
        : AppStrings.getWithLanguage(_currentLanguage, 'daily_goal_days_left')
            .replaceAll('{days}', plan.daysRemaining.toString());
    final habitRemaining = max(
      0,
      10 - userStateProvider.dailyQuizCount,
    );

    return Container(
      padding: EdgeInsets.all(isRoadHero ? 16 : 14),
      decoration: BoxDecoration(
        color: isRetro
            ? AppTheme.retroSurface
            : isRoadHero
                ? colorScheme.surface
                : colorScheme.surface.withOpacity(0.62),
        borderRadius: isRetro ? BorderRadius.zero : BorderRadius.circular(18),
        border: Border.all(
          color: isRetro
              ? AppTheme.retroLine
              : isRoadHero
                  ? (isDark ? AppTheme.roadNightPrimary : AppTheme.roadPrimary)
                  : colorScheme.onSurface.withOpacity(0.1),
          width: isRoadHero ? 2 : 1,
        ),
        boxShadow: isRoadHero
            ? AppTheme.chunkyShadowFor(
                context,
                color: isDark ? Colors.black : AppTheme.roadPrimaryDark,
              )
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isRetro
                      ? AppTheme.retroPageAlt
                      : primaryColor.withOpacity(0.12),
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.flag_rounded,
                  color: primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.getWithLanguage(
                          _currentLanguage, 'daily_goal_today'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      estimatedText,
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
          const SizedBox(height: 10),
          _DailyPlanProgressRow(
            icon: Icons.auto_awesome_rounded,
            label: AppStrings.getWithLanguage(
              _currentLanguage,
              'daily_goal_new_questions',
            ),
            completed: userStateProvider.dailyNewQuestionCount,
            goal: plan.newGoal,
            color: primaryColor,
          ),
          const SizedBox(height: 9),
          _DailyPlanProgressRow(
            icon: Icons.replay_rounded,
            label: AppStrings.getWithLanguage(
              _currentLanguage,
              'daily_goal_review_questions',
            ),
            completed: userStateProvider.dailyReviewQuestionCount,
            goal: plan.reviewGoal,
            color: reviewColor,
          ),
          const SizedBox(height: 7),
          Row(
            key: const Key('spaced_review_status'),
            children: [
              const SizedBox(width: 24),
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: reviewColor,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  AppStrings.getWithLanguage(
                    _currentLanguage,
                    'spaced_review_status',
                  ).replaceAll(
                    '{count}',
                    userStateProvider.dueReviewCount.toString(),
                  ),
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Builder(builder: (context) {
            final large = _isLargeTextScale(context);
            final status = Text(
              streak.activeToday
                  ? AppStrings.getWithLanguage(
                      _currentLanguage,
                      'learning_streak_active_today',
                    )
                  : AppStrings.getWithLanguage(
                      _currentLanguage,
                      'learning_streak_remaining',
                    ).replaceAll('{count}', habitRemaining.toString()),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: streak.activeToday
                    ? isRetro || isRoadHero
                        ? streakColor
                        : const Color(0xFFD97706)
                    : colorScheme.onSurfaceVariant,
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 18,
                      color: streakColor,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        AppStrings.getWithLanguage(
                          _currentLanguage,
                          'learning_streak_days',
                        ).replaceAll('{count}', streak.current.toString()),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (!large) Flexible(child: status),
                  ],
                ),
                if (large)
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.only(start: 23, top: 4),
                    child: status,
                  ),
              ],
            );
          }),
          const SizedBox(height: 12),
          DecoratedBox(
            // 厚底按鈕：實色陰影只在可點擊時出現。
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: isRoadHero && userStateProvider.canPractice()
                  ? AppTheme.chunkyShadowFor(context, color: AppTheme.roadInk)
                  : null,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('start_daily_plan_button'),
                onPressed: !canPractice
                    ? null
                    : planComplete
                        ? () => _startExtraRound(userStateProvider)
                        : () => _startDailyPlan(userStateProvider),
                icon: Icon(
                  isRoadHero && !canPractice
                      ? Icons.lock_clock_rounded
                      : planComplete
                          ? Icons.replay_rounded
                          : Icons.play_arrow_rounded,
                  size: 20,
                  color: isRetro ? AppTheme.retroPage : null,
                ),
                label: Text(
                  AppStrings.getWithLanguage(
                    _currentLanguage,
                    // 道路主題下額度用完直接說明原因，而不是只顯示灰掉的按鈕。
                    isRoadHero && !canPractice
                        ? 'quiz_limit_reached'
                        : planComplete
                            ? 'daily_goal_extra_round'
                            : 'daily_goal_start_today_plan',
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: isRoadHero ? 14 : 10),
          _buildTodayRecommendation(userStateProvider, context),
        ],
      ),
    );
  }

  Future<void> _startDailyPlan(UserStateProvider provider) async {
    await provider.checkAndResetDailyCounters();
    await provider.refreshDueReviewCount();
    if (!mounted || !provider.canPractice()) return;

    final plan = provider.currentDailyPlan;
    final newNeeded = max(0, plan.newGoal - provider.dailyNewQuestionCount);
    final reviewNeeded =
        max(0, plan.reviewGoal - provider.dailyReviewQuestionCount);
    final totalNeeded = newNeeded + reviewNeeded;
    if (totalNeeded == 0) {
      _showDailyPlanMessage('daily_goal_plan_complete');
      return;
    }

    final quota = provider.isVip
        ? min(totalNeeded, 300)
        : min(
            totalNeeded,
            AccessPolicy.freeDailyQuizLimit - provider.dailyQuizCount,
          );
    if (quota <= 0) return;

    final newCount = totalNeeded == 0
        ? 0
        : min(newNeeded, (quota * newNeeded / totalNeeded).ceil());
    final reviewCount = min(reviewNeeded, quota - newCount);
    final questions = await DatabaseService.getStudyPlanQuestions(
      newCount: newCount,
      reviewCount: reviewCount,
      translationLang: provider.currentLanguage,
      userId: provider.effectiveUserId,
    );
    if (!mounted) return;
    if (questions.isEmpty) {
      _showDailyPlanMessage('daily_goal_no_plan_questions');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeScreen(
          questions: questions,
          skipMastered: false,
        ),
      ),
    );
    if (mounted) await _loadStatistics();
  }

  /// 今日計劃完成後的「再練一組」：再來一組沒做過的新題，
  /// 與「今日建議」（錯題／薄弱章節）區分開。
  static const int _extraRoundSize = 10;

  Future<void> _startExtraRound(UserStateProvider provider) async {
    await provider.checkAndResetDailyCounters();
    if (!mounted || !provider.canPractice()) return;

    final count = provider.isVip
        ? _extraRoundSize
        : min(
            _extraRoundSize,
            AccessPolicy.freeDailyQuizLimit - provider.dailyQuizCount,
          );
    if (count <= 0) return;
    final questions = await DatabaseService.getStudyPlanQuestions(
      newCount: count,
      reviewCount: 0,
      translationLang: provider.currentLanguage,
      userId: provider.effectiveUserId,
    );
    if (!mounted) return;
    if (questions.isEmpty) {
      _showDailyPlanMessage('daily_goal_all_done');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeScreen(
          questions: questions,
          skipMastered: false,
        ),
      ),
    );
    if (mounted) await _loadStatistics();
  }

  void _showDailyPlanMessage(String key) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.getWithLanguage(_currentLanguage, key)),
      ),
    );
  }

  Widget _buildTodayRecommendation(
    UserStateProvider userStateProvider,
    BuildContext themeContext,
  ) {
    if (!userStateProvider.canPractice()) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(themeContext).colorScheme;

    final hasMistakes = userStateProvider.mistakeCount > 0;
    final hasAvailableWeakChapter = _recommendedWeakChapterId != null &&
        !userStateProvider.isChapterLocked(_recommendedWeakChapterId!);
    final recommendationKey = hasMistakes
        ? 'growth_recommend_mistakes'
        : hasAvailableWeakChapter
            ? 'growth_recommend_weak_chapter'
            : 'growth_recommend_random';
    final icon = hasMistakes
        ? Icons.report_outlined
        : hasAvailableWeakChapter
            ? Icons.menu_book_outlined
            : Icons.shuffle_rounded;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Builder(builder: (context) {
        final large = _isLargeTextScale(context);
        final startButton = TextButton(
          onPressed: () => _startTodayRecommendation(userStateProvider),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            AppStrings.getWithLanguage(_currentLanguage, 'growth_start'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        );
        final leading = Icon(icon, size: 20, color: colorScheme.primary);
        final texts = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            large
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      AppStrings.getWithLanguage(
                        _currentLanguage,
                        'growth_today_recommendation',
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  )
                : Text(
                    AppStrings.getWithLanguage(
                      _currentLanguage,
                      'growth_today_recommendation',
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
            const SizedBox(height: 2),
            Text(
              AppStrings.getWithLanguage(
                _currentLanguage,
                recommendationKey,
              ),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
        if (large) {
          // 大字级：图标、文字、按钮纵向堆叠，文字独占整行宽度。
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(height: 6),
              texts,
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: startButton,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: 8),
            Expanded(child: texts),
            startButton,
          ],
        );
      }),
    );
  }

  Future<void> _startTodayRecommendation(
    UserStateProvider userStateProvider,
  ) async {
    await userStateProvider.checkAndResetDailyCounters();
    if (!mounted || !userStateProvider.canPractice()) return;

    if (userStateProvider.mistakeCount > 0) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const MistakeReviewScreen(),
        ),
      );
    } else if (_recommendedWeakChapterId != null &&
        !userStateProvider.isChapterLocked(_recommendedWeakChapterId!)) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PracticeScreen(
            chapterId: _recommendedWeakChapterId,
            skipMastered: userStateProvider.skipMastered,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PracticeScreen(
            skipMastered: userStateProvider.skipMastered,
          ),
        ),
      );
    }

    if (mounted) {
      await userStateProvider.syncProgressToCloudIfVip();
      await _loadStatistics();
    }
  }

  /// 顯示訂閱引導彈窗（標題、內容、返回首頁 / 去訂閱解鎖）
  Future<bool?> _showSubscriptionDialog(
    BuildContext context,
    String title,
    String content,
  ) async {
    final currentLang = _currentLanguage;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final warningColor = AppTheme.warningTextFor(dialogContext);
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
          content: Text(content, style: const TextStyle(fontSize: 16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child:
                  Text(AppStrings.getWithLanguage(currentLang, 'return_home')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryFor(dialogContext),
                foregroundColor: Theme.of(dialogContext).colorScheme.onPrimary,
              ),
              child: Text(
                AppStrings.getWithLanguage(currentLang, 'go_subscribe_unlock'),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 檢查並導航到模擬考試（使用 canStartExam 權限判定）
  Future<void> _checkAndNavigateToMockTest(BuildContext context) async {
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    await userStateProvider.checkAndResetDailyCounters();
    if (!context.mounted) return;

    if (!userStateProvider.canStartExam()) {
      final result = await _showSubscriptionDialog(
        context,
        AppStrings.getWithLanguage(_currentLanguage, 'exam_limit_reached'),
        AppStrings.getWithLanguage(_currentLanguage, 'exam_limit_message'),
      );
      if (!context.mounted) return;
      if (result == true) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SubscriptionPage(),
          ),
        );
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MockTestScreen(),
      ),
    );
  }

  /// 獲取"題"的翻譯（根據當前語言）
  String _getQuestionText() {
    // 為了簡化，這裡直接返回中文"題"，實際可以根據語言返回不同的翻譯
    // 由於不同語言的語序可能不同，這裡使用簡單的方式
    if (_currentLanguage == 'it') return 'domande';
    if (_currentLanguage == 'en') return 'questions';
    if (_currentLanguage == 'ru') return 'задач';
    if (_currentLanguage == 'ur') return 'سوالات';
    if (_currentLanguage == 'pa') return 'ਸਵਾਲ';
    if (_currentLanguage == 'uk') return 'питань';
    return '题'; // 默認中文
  }

  /// 構建功能卡片（使用玻璃態卡片）
  /// 章節掌握率達到此比例即視為「已通過這一站」。
  static const double _routeStationDoneRatio = 0.8;

  /// 首頁學習路線：顯示當前章節前後共 4 站，點擊進入章節選擇。
  Widget _buildLearningRoute(
    BuildContext context,
    UserStateProvider userStateProvider,
  ) {
    final chapters = [...ChapterConfig.chapters]
      ..sort((a, b) => a.id.compareTo(b.id));
    if (chapters.isEmpty) return const SizedBox.shrink();

    int percentOf(int chapterId) {
      final progress = _chapterProgress[chapterId];
      final total = progress?['total'] ?? 0;
      if (total == 0) return 0;
      return ((progress?['mastered'] ?? 0) * 100 / total).floor();
    }

    bool isDone(int chapterId) =>
        percentOf(chapterId) >= _routeStationDoneRatio * 100;

    var currentIndex = chapters.indexWhere((chapter) =>
        !isDone(chapter.id) && !userStateProvider.isChapterLocked(chapter.id));
    if (currentIndex < 0) {
      currentIndex = chapters.indexWhere((chapter) => !isDone(chapter.id));
    }
    if (currentIndex < 0) currentIndex = chapters.length - 1;

    const windowSize = 4;
    var start = max(0, currentIndex - 1);
    final end = min(chapters.length, start + windowSize);
    start = max(0, end - windowSize);

    final stations = [
      for (var i = start; i < end; i++)
        LearningRouteStation(
          chapterId: chapters[i].id,
          title: chapters[i].getTitle(_currentLanguage),
          masteredPercent: percentOf(chapters[i].id),
          isDone: isDone(chapters[i].id),
          isCurrent: i == currentIndex,
          isLocked: userStateProvider.isChapterLocked(chapters[i].id),
        ),
    ];
    final doneCount = chapters.where((chapter) => isDone(chapter.id)).length;

    String text(String key) =>
        AppStrings.getWithLanguage(_currentLanguage, key);

    return LearningRouteCard(
      key: const Key('home_learning_route'),
      title: text('learning_route_title'),
      summary: text('learning_route_summary')
          .replaceAll('{done}', '$doneCount')
          .replaceAll('{total}', '${chapters.length}'),
      stations: stations,
      stationLabel: (station) {
        final key = station.isLocked
            ? 'learning_route_station_locked'
            : station.isCurrent
                ? 'learning_route_station_current'
                : 'learning_route_station';
        return text(key)
            .replaceAll('{n}', '${station.chapterId}')
            .replaceAll('{percent}', '${station.masteredPercent}');
      },
      onStationTap: (station) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ChapterSelectionScreen(focusChapterId: station.chapterId),
          ),
        );
      },
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback? onTap,
    RoadSignKind? sign,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRetro = AppTheme.isRetroFor(context);
    // 道路主題用路牌圖標取代方塊圖示；復古與 Web 保持原樣。
    final useSign = sign != null && AppTheme.usesRoadPalette && !isRetro;
    final effectiveIconColor = isRetro ? AppTheme.retroPrimary : iconColor;
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (useSign)
            RoadSignIcon(kind: sign, size: 56)
          else
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isRetro
                  ? AppTheme.retroPageAlt
                  : isDark
                      ? iconColor.withOpacity(0.16)
                      : bgColor,
              borderRadius:
                  isRetro ? BorderRadius.zero : BorderRadius.circular(16),
              border: isRetro ? Border.all(color: AppTheme.retroLine) : null,
              boxShadow: isRetro || AppTheme.usesRoadPalette
                  ? const []
                  : [
                      BoxShadow(
                        color: iconColor.withOpacity(0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                        spreadRadius: 0,
                      ),
                      BoxShadow(
                        color: isDark
                            ? Colors.white.withOpacity(0.04)
                            : Colors.white.withOpacity(0.8),
                        blurRadius: 0,
                        offset: const Offset(-1, -1),
                        spreadRadius: 0,
                      ),
                    ],
            ),
            child: Icon(
              icon,
              size: 28,
              color: effectiveIconColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              letterSpacing: 0.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// 構建收藏按鈕（始終可點擊：未就緒時提示，就緒時跳轉）
  Widget _buildFavoriteButton(BuildContext context, bool isDbReady) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (!isDbReady) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppStrings.get('database_loading_please_wait')),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const FavoriteReviewScreen(),
          ),
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border,
            size: 18,
            color: AppTheme.isRetroFor(context)
                ? AppTheme.retroPrimary
                : AppTheme.dangerFor(context).withOpacity(0.7),
          ),
          const SizedBox(width: 8),
          Text(
            AppStrings.get('favorite_questions'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
