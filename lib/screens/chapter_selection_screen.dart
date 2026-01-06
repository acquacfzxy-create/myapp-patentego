import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/chapter_config.dart';
import '../models/chapter.dart';
import '../config/app_strings.dart';
import '../providers/user_state_provider.dart';
import '../services/database_service.dart';
import 'practice_screen.dart';

/// 章節選擇頁面
/// 顯示所有章節，分為重點章節和其他章節兩組
class ChapterSelectionScreen extends StatefulWidget {
  const ChapterSelectionScreen({super.key});

  @override
  State<ChapterSelectionScreen> createState() => _ChapterSelectionScreenState();
}

class _ChapterSelectionScreenState extends State<ChapterSelectionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 導航到練習頁面
  void _navigateToPractice(BuildContext context, int chapterId) {
    print('📖 [ChapterSelection] 用戶點擊章節，準備跳轉到練習頁面');
    print('📖 [ChapterSelection] 傳遞的 chapterId: $chapterId (類型: ${chapterId.runtimeType})');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PracticeScreen(
          chapterId: chapterId,
          skipMastered: false, // 章節練習模式默認不過濾已掌握題目
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 獲取當前語言
    final currentLanguage = Provider.of<UserStateProvider>(context).currentLanguage;
    
    // 獲取重點章節和次要章節
    final principalChapters = ChapterConfig.principalChapters;
    final secondaryChapters = ChapterConfig.secondaryChapters;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('select_chapter')),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              text: '重點章節 (Argomenti Principali)',
              icon: Icon(Icons.star, size: 20),
            ),
            Tab(
              text: '次要章節 (Argomenti Secondari)',
              icon: Icon(Icons.book, size: 20),
            ),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 重點章節列表
          _buildChapterList(context, principalChapters, currentLanguage, isPrincipal: true),
          // 次要章節列表
          _buildChapterList(context, secondaryChapters, currentLanguage, isPrincipal: false),
        ],
      ),
    );
  }

  /// 構建章節列表
  Widget _buildChapterList(
    BuildContext context,
    List<ChapterModel> chapters,
    String currentLanguage, {
    required bool isPrincipal,
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
      padding: const EdgeInsets.all(16),
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        print('📋 [ChapterSelection] 構建章節卡片 - 索引: $index, 章節ID: ${chapter.id}, 標題: ${chapter.titleIt}');
        
        return _buildChapterCard(
          context,
          chapter,
          currentLanguage,
          isPrincipal: isPrincipal,
          onTap: () {
            print('👆 [ChapterSelection] 用戶點擊章節卡片 - 章節ID: ${chapter.id}');
            _navigateToPractice(context, chapter.id);
          },
        );
      },
    );
  }

  /// 構建章節卡片
  Widget _buildChapterCard(
    BuildContext context,
    ChapterModel chapter,
    String currentLanguage, {
    required bool isPrincipal,
    required VoidCallback onTap,
  }) {
    final chapterNumber = chapter.id.toString().padLeft(2, '0');
    final titleIt = chapter.titleIt;
    final titleTranslation = chapter.getTitle(currentLanguage);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
              // 左側：章節信息和標誌
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 章節序號和權重標誌
                    Row(
                      children: [
                        Text(
                          'Argomento $chapterNumber',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 重點章節權重標誌（紅色火苗圖標）
                        if (isPrincipal)
                          Row(
                            children: [
                              const Icon(
                                Icons.local_fire_department,
                                size: 18,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '重要',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red[700],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 意大利語標題（加粗）
                    Text(
                      titleIt,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 翻譯標題（副標題）
                    Text(
                      titleTranslation,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              // 右側：進度顯示（預留）
              _buildProgressIndicator(context, chapter.id),
            ],
          ),
        ),
      ),
    );
  }

  /// 構建進度指示器（顯示掌握進度）
  Widget _buildProgressIndicator(BuildContext context, int chapterId) {
    return FutureBuilder<Map<String, int>>(
      future: DatabaseService.getChapterProgress(chapterId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(strokeWidth: 3),
          );
        }
        
        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey[300]!,
                width: 3,
              ),
            ),
            child: Center(
              child: Text(
                '0%',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }
        
        final progress = snapshot.data!;
        final total = progress['total'] ?? 0;
        final mastered = progress['mastered'] ?? 0;
        
        if (total == 0) {
          return Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey[300]!,
                width: 3,
              ),
            ),
            child: Center(
              child: Text(
                '0%',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }
        
        final percentage = (mastered / total * 100).round();
        
        return Container(
          width: 50,
          height: 50,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 進度圓環
              SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  value: mastered / total,
                  strokeWidth: 4,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    percentage >= 100 ? Colors.green : Colors.blue,
                  ),
                ),
              ),
              // 百分比文字
              Text(
                '$percentage%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: percentage >= 100 ? Colors.green : Colors.blue,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
