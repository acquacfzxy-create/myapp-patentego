import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'practice_screen.dart';
import 'mock_test_screen.dart';
import 'settings_screen.dart';
import 'mistake_review_screen.dart';
import 'favorite_review_screen.dart';
import 'chapter_selection_screen.dart';
import '../services/database_service.dart';
import '../config/app_strings.dart';
import '../providers/user_state_provider.dart';

/// 首頁
/// 提供應用的主要功能入口
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _totalQuestions = 0;
  int _answeredQuestions = 0;
  int? _bestScore;
  bool _isLoadingStats = true;
  bool _skipMasteredQuestions = false; // 是否跳过已掌握题目

  // 獲取當前語言（用於動態字體和 RTL）
  String get _currentLanguage {
    try {
      return Provider.of<UserStateProvider>(context, listen: false).currentLanguage;
    } catch (e) {
      return 'zh'; // 默認值
    }
  }

  // 判斷是否為長文本語言（需要較小字體）
  bool get _isLongTextLanguage => _currentLanguage == 'ru' || _currentLanguage == 'uk';

  // 判斷是否為 RTL 語言
  bool get _isRTL => _currentLanguage == 'ur' || _currentLanguage == 'pa';

  // 根據語言動態獲取字體大小
  double _getFontSize(double baseSize) {
    return _isLongTextLanguage ? baseSize - 2 : baseSize;
  }

  @override
  void initState() {
    super.initState();
    _checkDatabaseStatus();
    _loadStatistics();
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

  /// 加載統計信息
  Future<void> _loadStatistics() async {
    if (!DatabaseService.isInitialized) return;

    setState(() {
      _isLoadingStats = true;
    });

    try {
      final total = await DatabaseService.getTotalQuestionsCount();
      final answered = await DatabaseService.getAnsweredQuestionsCount();
      final bestScore = await DatabaseService.getBestMockTestScore();

      if (mounted) {
        setState(() {
          _totalQuestions = total;
          _answeredQuestions = answered;
          _bestScore = bestScore;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStats = false;
        });
      }
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

  Widget _buildHomeContent(BuildContext context, String? dbError, bool isDbReady) {
    
    // 顯示數據庫錯誤提示
    if (dbError != null && !isDbReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppStrings.get('database_init_failed')}\n${AppStrings.get('errors')}: $dbError'),
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
      appBar: AppBar(
        title: Text(AppStrings.get('app_title')),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // 禁用自動返回箭頭（首頁是根頁面）
        automaticallyImplyLeading: false,
        // 設置按鈕固定在 actions 中（RTL 模式下會自動鏡像位置，但圖標保持不變）
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: AppStrings.get('settings'),
            onPressed: () async {
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
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStatistics,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 頭部進度卡片
              _buildProgressCard(context),
              
              const SizedBox(height: 24),
              
              // 核心功能入口
              Text(
                AppStrings.get('select_mode'),
                style: TextStyle(
                  fontSize: _getFontSize(20),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              // GridView 功能入口
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
                children: [
                  _buildFeatureCard(
                    context,
                    title: AppStrings.get('random_practice'),
                    icon: Icons.list_alt,
                    color: Colors.blue,
                    onTap: isDbReady ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PracticeScreen(
                            skipMastered: _skipMasteredQuestions,
                          ),
                        ),
                      );
                    } : null,
                  ),
                  _buildFeatureCard(
                    context,
                    title: AppStrings.get('chapter_practice'),
                    icon: Icons.book,
                    color: Colors.orange,
                    onTap: isDbReady ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ChapterSelectionScreen(),
                        ),
                      );
                    } : null,
                  ),
                  _buildFeatureCard(
                    context,
                    title: AppStrings.get('official_mock_test'),
                    icon: Icons.timer,
                    color: Colors.teal,
                    onTap: isDbReady ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MockTestScreen(),
                        ),
                      );
                    } : null,
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // 跳过已掌握题目开关
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  title: Text(
                    AppStrings.get('skip_mastered_questions'),
                    style: TextStyle(
                      fontSize: _getFontSize(16),
                    ),
                  ),
                  value: _skipMasteredQuestions,
                  onChanged: isDbReady ? (bool value) {
                    setState(() {
                      _skipMasteredQuestions = value;
                    });
                  } : null,
                  secondary: const Icon(Icons.filter_list),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 底部功能區域
              Text(
                AppStrings.get('other_features'),
                style: TextStyle(
                  fontSize: _getFontSize(18),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              // 錯題回顧
              _buildBottomFeatureCard(
                context,
                title: AppStrings.get('mistake_review'),
                icon: Icons.assignment_late,
                color: Colors.red,
                onTap: isDbReady ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MistakeReviewScreen(),
                    ),
                  );
                } : null,
              ),
              
              const SizedBox(height: 12),
              
              // 收藏題目
              _buildBottomFeatureCard(
                context,
                title: AppStrings.get('favorite_questions'),
                icon: Icons.favorite,
                color: Colors.pink,
                onTap: isDbReady ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FavoriteReviewScreen(),
                    ),
                  );
                } : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 構建進度卡片
  Widget _buildProgressCard(BuildContext context) {
    const int totalQuestions = 7139;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primaryContainer,
            ],
          ),
        ),
        child: Consumer<UserStateProvider>(
          builder: (context, userStateProvider, child) {
            final masteredCount = userStateProvider.masteredCount;
            final percentage = (masteredCount / totalQuestions) * 100;
            final percentageText = percentage.toStringAsFixed(1);
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 標題
                Row(
                  children: [
                    Icon(
                      Icons.trending_up,
                      color: Colors.white,
                      size: _getFontSize(28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: _isRTL ? Alignment.centerRight : Alignment.centerLeft,
                        child: Text(
                          AppStrings.get('study_progress'),
                          style: TextStyle(
                            fontSize: _getFontSize(20),
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // 主體部分：左側百分比 + 中間進度條
                Row(
                  children: [
                    // 左側：百分比大數字
                    Directionality(
                      textDirection: TextDirection.ltr, // 數字始終保持 LTR
                      child: Text(
                        '$percentageText%',
                        style: TextStyle(
                          fontSize: _getFontSize(36),
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 中間：綠色進度條
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          minHeight: 12,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // 下方：小字顯示已掌握數量
                Directionality(
                  textDirection: TextDirection.ltr, // 數字始終保持 LTR
                  child: Text(
                    '${AppStrings.get('mastered_label')} $masteredCount / $totalQuestions ${_getQuestionText()}',
                    style: TextStyle(
                      fontSize: _getFontSize(14),
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
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
    return '題'; // 默認中文
  }

  /// 構建功能卡片（GridView 使用）
  Widget _buildFeatureCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: onTap == null ? Colors.grey[300] : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 48,
                color: onTap == null ? Colors.grey : color,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _getFontSize(16),
                    fontWeight: FontWeight.bold,
                    color: onTap == null ? Colors.grey : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 構建底部功能卡片
  Widget _buildBottomFeatureCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: _getFontSize(18),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                _isRTL ? Icons.chevron_left : Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
