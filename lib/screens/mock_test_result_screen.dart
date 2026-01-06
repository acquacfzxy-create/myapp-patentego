import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/mock_test_config.dart';
import '../config/app_strings.dart';
import '../config/chapter_config.dart';
import '../services/database_service.dart';
import '../providers/user_state_provider.dart';
import 'practice_screen.dart';
import 'mock_test_errors_screen.dart';

/// 模擬考試結果頁面
class MockTestResultScreen extends StatefulWidget {
  final int totalQuestions;
  final int correctAnswers;
  final int errors;
  final bool isPassed;
  final int timeRemaining;
  final List<String> errorIds;

  const MockTestResultScreen({
    super.key,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.errors,
    required this.isPassed,
    required this.timeRemaining,
    required this.errorIds,
  });

  @override
  State<MockTestResultScreen> createState() => _MockTestResultScreenState();
}

class _MockTestResultScreenState extends State<MockTestResultScreen> {
  Map<int, int> _chapterErrorDistribution = {};
  bool _isLoadingDistribution = true;

  @override
  void initState() {
    super.initState();
    _loadChapterErrorDistribution();
  }

  /// 加載章節錯誤分布
  Future<void> _loadChapterErrorDistribution() async {
    setState(() {
      _isLoadingDistribution = true;
    });

    try {
      final distribution = await DatabaseService.getChapterErrorDistribution(widget.errorIds);
      
      if (mounted) {
        setState(() {
          _chapterErrorDistribution = distribution;
          _isLoadingDistribution = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDistribution = false;
        });
      }
    }
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// 導航到指定章節的練習頁面
  void _navigateToChapterPractice(int chapterId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PracticeScreen(),
      ),
    );
  }

  /// 查看本套試卷的錯題
  void _viewTestErrors() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MockTestErrorsScreen(errorIds: widget.errorIds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLanguage = Provider.of<UserStateProvider>(context).currentLanguage;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('test_result')),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 判分儀式：IDONEO / NON IDONEO
            _buildResultBanner(),
            
            const SizedBox(height: 32),
            
            // 統計信息
            _buildStatisticsSection(),
            
            const SizedBox(height: 32),
            
            // 錯誤分布分析
            if (widget.errorIds.isNotEmpty) _buildErrorDistributionSection(currentLanguage),
            
            const SizedBox(height: 32),
            
            // 查看錯題按鈕
            if (widget.errorIds.isNotEmpty)
              _buildViewErrorsButton(),
            
            const SizedBox(height: 24),
            
            // 操作按鈕
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  /// 構建結果橫幅（IDONEO / NON IDONEO）
  Widget _buildResultBanner() {
    final isPassed = widget.errors <= MockTestConfig.maxErrors;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: isPassed ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPassed ? Colors.green : Colors.red,
          width: 3,
        ),
      ),
      child: Column(
        children: [
          // 圖標（煙花或警告）
          Icon(
            isPassed ? Icons.celebration : Icons.warning,
            size: 80,
            color: isPassed ? Colors.green[700] : Colors.red[700],
          ),
          const SizedBox(height: 16),
          // 大標題
          Text(
            isPassed ? AppStrings.get('idoneo') : AppStrings.get('non_idoneo'),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: isPassed ? Colors.green[900] : Colors.red[900],
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          // 副標題
          Text(
            isPassed ? AppStrings.get('passed') : AppStrings.get('failed'),
            style: TextStyle(
              fontSize: 20,
              color: isPassed ? Colors.green[700] : Colors.red[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 構建統計信息區域
  Widget _buildStatisticsSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildStatRow(
              AppStrings.get('correct_answers'), 
              '${widget.correctAnswers} / ${widget.totalQuestions}'
            ),
            const Divider(),
            _buildStatRow(
              AppStrings.get('error_count'),
              '${widget.errors} / ${MockTestConfig.maxErrors} (${AppStrings.get('max_allowed')})',
            ),
            const Divider(),
            _buildStatRow(
              AppStrings.get('time_remaining'), 
              _formatTime(widget.timeRemaining)
            ),
          ],
        ),
      ),
    );
  }

  /// 構建錯誤分布分析區域
  Widget _buildErrorDistributionSection(String currentLanguage) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.get('error_distribution'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            if (_isLoadingDistribution)
              const Center(child: CircularProgressIndicator())
            else if (_chapterErrorDistribution.isEmpty)
              Text(
                AppStrings.get('no_chapter_errors'),
                style: TextStyle(color: Colors.grey[600]),
              )
            else
              ...(_chapterErrorDistribution.entries.map((entry) {
                final chapterId = entry.key;
                final errorCount = entry.value;
                final chapter = ChapterConfig.getChapterById(chapterId);
                
                if (chapter == null) return const SizedBox.shrink();
                
                final chapterNumber = chapterId.toString().padLeft(2, '0');
                final chapterTitleIt = chapter.titleIt;
                final chapterTitleTranslation = chapter.getTitle(currentLanguage);
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        chapterNumber,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[900],
                        ),
                      ),
                    ),
                    title: Text(
                      'Argomento $chapterNumber',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(chapterTitleIt),
                        Text(
                          chapterTitleTranslation,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$errorCount ${AppStrings.get('errors_in_chapter')}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton(
                          onPressed: () => _navigateToChapterPractice(chapterId),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            minimumSize: const Size(0, 28),
                          ),
                          child: Text(
                            AppStrings.get('targeted_review'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              })),
          ],
        ),
      ),
    );
  }

  /// 構建查看錯題按鈕
  Widget _buildViewErrorsButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _viewTestErrors,
        icon: const Icon(Icons.error_outline),
        label: Text(AppStrings.get('view_test_errors')),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// 構建操作按鈕
  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          onPressed: () {
            // 返回首頁
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          icon: const Icon(Icons.home),
          label: Text(AppStrings.get('return_home')),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            // 重新開始考試
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.refresh),
          label: Text(AppStrings.get('restart')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
