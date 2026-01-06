import 'package:flutter/material.dart';
import '../models/question.dart';
import '../services/database_service.dart';
import '../config/app_strings.dart';

/// 題目顯示組件
/// 負責顯示題目內容、圖片、選項和解析
class QuestionWidget extends StatefulWidget {
  final Question question;
  final Function(bool) onAnswerSelected;
  final String currentLanguage;
  final int? currentIndex;
  final int? totalQuestions;
  final bool isExamMode; // 是否為考試模式

  const QuestionWidget({
    super.key,
    required this.question,
    required this.onAnswerSelected,
    required this.currentLanguage,
    this.currentIndex,
    this.totalQuestions,
    this.isExamMode = false, // 默認為練習模式
  });

  @override
  State<QuestionWidget> createState() => _QuestionWidgetState();
}

class _QuestionWidgetState extends State<QuestionWidget> {
  bool _showExplanation = false;
  bool _isFavorite = false;
  bool _showTranslation = false; // 翻譯顯示狀態
  final ScrollController _scrollController = ScrollController(); // 用於自動滾動

  @override
  void initState() {
    super.initState();
    _loadFavoriteStatus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 當題目更新時，重置翻譯和解析顯示狀態
  @override
  void didUpdateWidget(QuestionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果題目ID改變，重置翻譯和解析顯示狀態
    if (oldWidget.question.id != widget.question.id) {
      setState(() {
        _showTranslation = false;
        _showExplanation = false;
      });
    }
  }

  /// 加載收藏狀態
  Future<void> _loadFavoriteStatus() async {
    final isFav = await DatabaseService.isFavorite(widget.question.id);
    if (mounted) {
      setState(() {
        _isFavorite = isFav;
      });
    }
  }

  /// 切換收藏狀態
  Future<void> _toggleFavorite() async {
    await DatabaseService.toggleFavorite(widget.question.id);
    if (mounted) {
      setState(() {
        _isFavorite = !_isFavorite;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFavorite 
              ? AppStrings.get('favorited') 
              : AppStrings.get('unfavorited')),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// 構建圖片組件（優化：使用緩存避免內存抖動）
  Widget _buildImageWidget(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) {
      return const SizedBox.shrink();
    }

    // 處理圖片路徑：如果是網絡URL則使用 Image.network，否則嘗試從 assets 加載
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.contain,
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
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
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
        fit: BoxFit.contain,
        cacheWidth: 800, // 限制最大寬度為 800px，減少內存占用
        errorBuilder: (context, error, stackTrace) {
          return _buildImageError();
        },
        // 添加載入指示器（雖然 assets 加載很快，但為了用戶體驗）
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: frame != null ? child : const SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator()),
            ),
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

  /// 自動滾動到底部（顯示新內容時）
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 默認顯示意大利語題目
    final questionTextIt = widget.question.getQuestionText('it') ?? 
                          widget.question.getQuestionText(widget.currentLanguage);
    
    // 獲取翻譯語言的題目內容（如果存在）
    final questionTextTranslation = widget.currentLanguage != 'it' 
        ? widget.question.getQuestionText(widget.currentLanguage)
        : null;
    
    // 獲取當前語言的解析內容
    final explanationText = widget.question.getExplanationText(widget.currentLanguage);

    // 使用 Column + Expanded 實現吸底布局
    return Column(
      children: [
        // 可滾動的內容區域
        Expanded(
          child: Stack(
            children: [
              // 滾動視圖
              SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), // 底部留出空間，避免被按鈕遮擋
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 進度顯示（模擬考試時顯示）
                    if (widget.currentIndex != null && widget.totalQuestions != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          '${AppStrings.get('question')} ${widget.currentIndex! + 1} ${AppStrings.get('of')} ${widget.totalQuestions}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),

                    // 收藏按鈕（右對齊）
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: Icon(
                            _isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: _isFavorite ? Colors.red : Colors.grey,
                          ),
                          onPressed: _toggleFavorite,
                          tooltip: _isFavorite 
                              ? AppStrings.get('unfavorite') 
                              : AppStrings.get('favorite'),
                        ),
                      ],
                    ),

                    // 圖片（如果有）
                    if (widget.question.imageName != null && widget.question.imageName!.isNotEmpty)
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          constraints: const BoxConstraints(
                            maxHeight: 300,
                            maxWidth: double.infinity,
                          ),
                          child: _buildImageWidget(widget.question.imageName),
                        ),
                      ),

                    // 題目內容（意大利語）
                    Text(
                      questionTextIt ?? AppStrings.get('question_content_missing'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 練習模式：翻譯和解析按鈕（固定在題目下方，水平排列）
                    if (!widget.isExamMode)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 翻譯按鈕（如果當前語言不是意大利語且有翻譯）
                          if (widget.currentLanguage != 'it' && questionTextTranslation != null && questionTextTranslation.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _showTranslation = !_showTranslation;
                                  // 如果隱藏翻譯，同時隱藏解析
                                  if (!_showTranslation) {
                                    _showExplanation = false;
                                  }
                                });
                              },
                              icon: Icon(_showTranslation ? Icons.visibility_off : Icons.translate),
                              label: Text(_showTranslation 
                                  ? AppStrings.get('hide_translation') 
                                  : AppStrings.get('show_translation')),
                            ),
                          
                          // 解析按鈕（只在顯示翻譯後才顯示）
                          if (_showTranslation && explanationText != null && explanationText.isNotEmpty)
                            const SizedBox(width: 12),
                          
                          if (_showTranslation && explanationText != null && explanationText.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _showExplanation = !_showExplanation;
                                });
                                // 顯示解析時自動滾動到底部
                                if (_showExplanation) {
                                  _scrollToBottom();
                                }
                              },
                              icon: Icon(_showExplanation
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              label: Text(_showExplanation 
                                  ? AppStrings.get('hide_explanation') 
                                  : AppStrings.get('show_explanation')),
                            ),
                        ],
                      ),

                    const SizedBox(height: 16),

                    // 翻譯內容（如果顯示）
                    if (!widget.isExamMode && _showTranslation && questionTextTranslation != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Text(
                          questionTextTranslation,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),

                    // 解析內容
                    if (!widget.isExamMode && _showExplanation && explanationText != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Text(
                          explanationText,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                  ],
                ),
              ),

              // 底部淡出漸變效果（提示下方還有內容）
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 40,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.0),
                          Colors.white.withValues(alpha: 1.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 固定的底部按鈕區域（不隨滾動移動）
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => widget.onAnswerSelected(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],  // 紅色代表 Falso
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    child: const Text(
                      'FALSO',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => widget.onAnswerSelected(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],  // 綠色代表 Vero
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    child: const Text(
                      'VERO',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
