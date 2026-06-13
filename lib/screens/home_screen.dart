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
import '../services/firebase_status.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../config/route_observer.dart';
import '../providers/user_state_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/circular_progress_card.dart';

/// 首頁
/// 提供應用的主要功能入口
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with RouteAware, TickerProviderStateMixin {
  // 動畫控制器
  late AnimationController _coverageAnimationController;
  late AnimationController _masteryAnimationController;
  late Animation<double> _coverageAnimation;
  late Animation<double> _masteryAnimation;

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
      userStateProvider.updateMasteryStats().catchError((e) {
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
      await userStateProvider.updateMasteryStats();

      if (mounted) {
        setState(() {});
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

        return _buildHomeContent(context, dbError, isDbReady);
      },
    );
  }

  Widget _buildHomeContent(
      BuildContext context, String? dbError, bool isDbReady) {
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
        decoration: AppTheme.pageDecoration,
        child: RefreshIndicator(
          onRefresh: _loadStatistics,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 自定义头部
              SliverToBoxAdapter(
                child: _buildHeader(context),
              ),
              // 进度卡片
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: _buildProgressCard(context),
                ),
              ),
              // 功能网格
              SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0,
                  ),
                  delegate: SliverChildListDelegate([
                    _buildFeatureCard(
                      context,
                      title: AppStrings.get('random_practice'),
                      icon: Icons.shuffle,
                      iconColor: AppTheme.primary,
                      bgColor: AppTheme.primarySoft,
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
                      icon: Icons.menu_book,
                      iconColor: AppTheme.roadGreen,
                      bgColor: AppTheme.roadGreenSoft,
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
                      icon: Icons.timer,
                      iconColor: AppTheme.warning,
                      bgColor: const Color(0xFFFFF7ED),
                      onTap: isDbReady
                          ? () {
                              _checkAndNavigateToMockTest(context);
                            }
                          : null,
                    ),
                    _buildFeatureCard(
                      context,
                      title: AppStrings.get('mistake_review'),
                      icon: Icons.report,
                      iconColor: AppTheme.danger,
                      bgColor: const Color(0xFFFEF2F2),
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
              // 收藏按钮
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: _buildFavoriteButton(context, isDbReady),
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 構建頭部（用戶信息 + 設置按鈕）
  Widget _buildHeader(BuildContext context) {
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
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.ink,
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
                          ? AppTheme.primary
                          : Colors.grey[600],
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
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.4),
                border: Border.all(
                  color: Colors.white.withOpacity(0.8),
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
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
                  child: const Icon(
                    Icons.settings,
                    color: AppTheme.muted,
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
                Row(
                  children: [
                    Text(
                      AppStrings.get('study_progress').toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[400],
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.primary.withOpacity(0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppStrings.getWithLanguage(
                                _currentLanguage, 'detailed_analysis'),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 9,
                            color: AppTheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
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
                        color: Colors.white.withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              AppStrings.get('covered_questions').toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0EA5E9),
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$attemptedCount ',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                  TextSpan(
                                    text: _getQuestionText(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.normal,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 36,
                        color: Colors.white.withOpacity(0.6),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              AppStrings.get('mastered_questions')
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$masteredCount ',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                  TextSpan(
                                    text: _getQuestionText(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.normal,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
        content: Text(content, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.getWithLanguage(currentLang, 'return_home')),
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
  Widget _buildFeatureCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback? onTap,
  }) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: iconColor.withOpacity(0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.8),
                  blurRadius: 0,
                  offset: const Offset(-1, -1),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 28,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
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
            color: AppTheme.danger.withOpacity(0.7),
          ),
          const SizedBox(width: 8),
          Text(
            AppStrings.get('favorite_questions'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.muted,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
