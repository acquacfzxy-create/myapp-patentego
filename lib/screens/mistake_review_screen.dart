import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../providers/user_state_provider.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/question_widget.dart';
import '../widgets/translation_panel.dart';
import '../models/question.dart';
import 'practice_screen.dart';
import 'mock_test_screen.dart';
import 'subscription_page.dart';

/// 錯題回顧頁面
/// 顯示用戶之前做錯的題目列表
/// UI 結構完全參照 ExamReviewScreen
class MistakeReviewScreen extends StatefulWidget {
  /// 初始選中的 Tab：0 = 專項複習，1 = 錯題列表
  final int initialTabIndex;

  const MistakeReviewScreen({super.key, this.initialTabIndex = 0});

  @override
  State<MistakeReviewScreen> createState() => _MistakeReviewScreenState();
}

class _MistakeReviewScreenState extends State<MistakeReviewScreen> {
  List<WrongQuestionEntry> _errorQuestions = [];
  bool _isLoading = true;

  // Tab 切換狀態：0 = 專項複習，1 = 錯題列表
  late int _selectedTab;

  // 記錄每道題的展開狀態（翻譯、解析）
  final Map<String, bool> _showTranslation = {};
  final Map<String, bool> _showExplanation = {};

  // 當前語言（從 Provider 獲取）
  String get _currentLanguage =>
      Provider.of<UserStateProvider>(context, listen: false).currentLanguage;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTabIndex.clamp(0, 1);
    _loadErrorQuestions();
  }

  /// 加載錯題列表
  Future<void> _loadErrorQuestions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userStateProvider =
          Provider.of<UserStateProvider>(context, listen: false);
      // 使用當前語言查詢，確保能獲取對應語言的翻譯和解析
      final questions = await DatabaseService.getWrongQuestions(
        userStateProvider.effectiveUserId,
        lang: _currentLanguage,
      );

      setState(() {
        _errorQuestions = questions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.get('failed_to_load')}: $e')),
        );
      }
    }
  }

  /// 切換翻譯顯示
  void _toggleTranslation(String questionId) {
    setState(() {
      _showTranslation[questionId] = !(_showTranslation[questionId] ?? false);
      if (_showTranslation[questionId] == true) {
        _showExplanation[questionId] = false; // 關閉解析
      }
    });
  }

  /// 點擊解析圖標：展開時先做限額檢查與計次，與練習模式一致
  Future<void> _onExplanationIconTap(String questionId) async {
    final isOpening = _showExplanation[questionId] != true;
    if (!isOpening) {
      setState(() {
        _showExplanation[questionId] = false;
        _showTranslation[questionId] = false;
      });
      return;
    }

    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
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

    await userStateProvider.incrementExplanationCount(questionId);
    if (mounted) {
      setState(() {
        _showExplanation[questionId] = true;
        _showTranslation[questionId] = false;
      });
    }
  }

  /// 切換收藏狀態
  Future<void> _toggleFavorite(String questionId) async {
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);

    await DatabaseService.toggleFavorite(
      questionId,
      userId: userStateProvider.effectiveUserId,
    );

    setState(() {}); // 刷新UI
  }

  /// 檢查是否收藏
  Future<bool> _isFavorite(String questionId) async {
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    return await DatabaseService.isFavorite(
      questionId,
      userId: userStateProvider.effectiveUserId,
    );
  }

  /// 從錯題列表中移除題目
  Future<void> _removeFromMistakes(String questionId) async {
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);

    try {
      await DatabaseService.removeQuestionFromMistakes(
        questionId,
        userId: userStateProvider.effectiveUserId,
      );

      // 從列表中移除
      setState(() {
        _errorQuestions.removeWhere((entry) => entry.question.id == questionId);
      });

      // 刷新錯題統計
      userStateProvider.refreshMistakeCount();

      // 顯示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.get('removed_from_mistakes')),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppStrings.get('failed_to_remove')}: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 顯示移除確認對話框
  Future<void> _showRemoveConfirmationDialog(String questionId) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            backgroundColor: Colors.white.withOpacity(0.95),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              AppStrings.get('remove_from_mistakes_title'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
            content: Text(
              AppStrings.get('remove_from_mistakes_message'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
            actions: [
              // 取消按鈕
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  AppStrings.get('cancel'),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ),
              // 確認移除按鈕
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[400],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  AppStrings.get('confirm_remove'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true && mounted) {
      await _removeFromMistakes(questionId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 毛玻璃 AppBar（參照 ExamReviewScreen）
      appBar: _buildGlassAppBar(context),
      body: Container(
        decoration: AppTheme.pageDecoration,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorQuestions.isEmpty
                ? _buildEmptyMistakesState(context)
                : Column(
                    children: [
                      // Tab 切換欄
                      _buildTabBar(),
                      // 內容區域
                      Expanded(
                        child: _selectedTab == 0
                            ? _buildPracticeGuide()
                            : _buildBrowseList(),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildEmptyMistakesState(BuildContext context) {
    return EmptyStateView(
      icon: Icons.assignment_turned_in_outlined,
      title: AppStrings.get('empty_mistakes_title'),
      description: AppStrings.get('empty_mistakes_description'),
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
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const MockTestScreen(),
            ),
          );
        },
        child: Text(
          AppStrings.get('start_mock_exam_now'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// 構建 Tab 切換欄
  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              label: AppStrings.get('mistake_tab_practice'),
              isSelected: _selectedTab == 0,
              onTap: () => setState(() => _selectedTab = 0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTabButton(
              label: AppStrings.get('mistake_tab_list'),
              isSelected: _selectedTab == 1,
              onTap: () => setState(() => _selectedTab = 1),
            ),
          ),
        ],
      ),
    );
  }

  /// 構建 Tab 按鈕
  Widget _buildTabButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? const Color(0xFF137FEC) : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  /// 構建瀏覽列表（原有功能）
  Widget _buildBrowseList() {
    return Consumer<UserStateProvider>(
      builder: (context, userStateProvider, child) {
        final totalMistakes = userStateProvider.mistakeCount;
        final isVip = userStateProvider.isVip;

        // ─── 計算列表顯示長度（截斷非會員的錯題列表） ─────────────────────
        int itemCount;
        if (isVip) {
          // VIP：顯示完整錯題列表
          itemCount = _errorQuestions.length;
        } else {
          // 非會員：限制列表長度
          if (totalMistakes <= 10) {
            // 錯題數量不超過 10：顯示實際數量
            itemCount = _errorQuestions.length;
          } else {
            // 錯題數量大於 10：顯示 12 個條目
            // [0-9] 十道可見錯題 + [10] 升級橫幅 + [11] 模糊鎖定 Teaser
            itemCount = 12;
          }
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            // ─── VIP：沿用原有邏輯，完整渲染鎖定 / 非鎖定 ────────────────
            if (isVip || totalMistakes <= 10) {
              final entry = _errorQuestions[index];
              final isLocked = userStateProvider.shouldLockMistake(index);

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: isLocked
                    ? _buildLockedCard(entry, index, totalMistakes)
                    : _buildQuestionCard(entry, index),
              );
            }

            // ─── 非會員且 totalMistakes > 10：固定 12 項結構 ───────────────
            // [0-9]：前 10 道正常題目
            // [10]：升級橫幅（唯一一張）
            // [11]：第一道鎖定題作為模糊 Teaser

            if (index <= 9) {
              // 安全防護：如果實際錯題少於 index+1，就不渲染
              if (index >= _errorQuestions.length) {
                return const SizedBox.shrink();
              }
              final entry = _errorQuestions[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildQuestionCard(entry, index),
              );
            } else if (index == 10) {
              // 升級橫幅，與上下卡片間距使用統一的 16
              final hiddenCount = (totalMistakes - 10).clamp(0, totalMistakes);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildUnlockBanner(hiddenCount: hiddenCount),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            } else if (index == 11) {
              // 第一張鎖定卡片作為 Teaser（如果存在第 11 題）
              if (_errorQuestions.length <= 10) {
                return const SizedBox.shrink();
              }
              final lockedEntry = _errorQuestions[10]; // 第 11 題，index=10
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildLockedCard(lockedEntry, 10, totalMistakes),
              );
            }

            // 理論上不會觸達這裡（itemCount 已限制為 12）
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  /// 構建專項複習引導卡片
  Widget _buildPracticeGuide() {
    final mistakeCount = _errorQuestions.length;
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: true);
    final isVip = userStateProvider.isVip;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(32),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 圖標
                  const Icon(
                    Icons.psychology,
                    size: 80,
                    color: Color(0xFF137FEC),
                  ),
                  const SizedBox(height: 24),
                  // 標題
                  Text(
                    AppStrings.get('mistake_mode_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D131B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 描述
                  Text(
                    '${AppStrings.get('mistake_mode_description').replaceAll('{count}', '$mistakeCount')}\n'
                    '${AppStrings.get('mistake_mode_vip_suffix')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // 開始按鈕
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: mistakeCount > 0
                          ? () {
                              if (!isVip) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const SubscriptionPage(),
                                  ),
                                );
                              } else {
                                _startMistakePractice();
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isVip ? const Color(0xFF137FEC) : Colors.white,
                        foregroundColor:
                            isVip ? Colors.white : const Color(0xFFB45309),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isVip
                              ? BorderSide.none
                              : const BorderSide(
                                  color: Color(0xFFF59E0B),
                                  width: 1.2,
                                ),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVip
                                ? Icons.workspace_premium
                                : Icons.lock_outline,
                            size: 18,
                            color:
                                isVip ? Colors.white : const Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppStrings.get('mistake_mode_title'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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
        ),
      ),
    );
  }

  /// 開始專項複習
  Future<void> _startMistakePractice() async {
    if (_errorQuestions.isEmpty) return;

    // 提取所有題目
    final questions = _errorQuestions.map((entry) => entry.question).toList();

    // 跳轉到練習模式，傳入錯題列表和錯題模式標記
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PracticeScreen(
          questions: questions,
          isMistakeMode: true,
        ),
      ),
    );

    if (!mounted) return;
    await Provider.of<UserStateProvider>(context, listen: false)
        .syncProgressToCloudIfVip();
    await _loadErrorQuestions();
  }

  /// 構建毛玻璃 AppBar（參照 ExamReviewScreen）
  PreferredSizeWidget _buildGlassAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              border: Border(
                bottom: BorderSide(
                  color: Colors.black.withOpacity(0.05),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 左側：返回按鈕
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      color: const Color(0xFF475569),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    // 中間：標題
                    Expanded(
                      child: Center(
                        child: Text(
                          AppStrings.get('mistake_review'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ),
                    // 右側：占位
                    const SizedBox(width: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 構建題目卡片（完全參照 ExamReviewScreen）
  Widget _buildQuestionCard(WrongQuestionEntry entry, int index) {
    final question = entry.question;
    final correctAnswer = question.answer;
    final questionId = question.id;

    // 獲取題目文本：默認顯示意大利語原文
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
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左欄 (Gutter)：題號 + 正確答案圓圈（極簡版）
                    _buildLeftGutter(index, correctAnswer, entry.wrongCount),
                    const SizedBox(width: 12),

                    // 中欄 (Content)：題目內容
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: hasImage
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        children: [
                          // 意語題目文本（統一行高1.5）
                          Text(
                            questionText,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.5, // 統一行高
                              color: Color(0xFF0D131B),
                            ),
                          ),

                          // 圖片（如果有），與文字保持垂直間距，避免任何重疊
                          if (hasImage) ...[
                            const SizedBox(height: 12),
                            _buildQuestionImage(question.imageName!),
                          ],

                          // 翻譯內容（如果展開）
                          if (_showTranslation[questionId] == true &&
                              translationText != null) ...[
                            const SizedBox(height: 16),
                            TranslationPanel(
                              text: translationText,
                              languageCode: _currentLanguage,
                            ),
                          ],

                          // 關鍵詞（如果展開翻譯，與翻譯文本間距8px）
                          if (_showTranslation[questionId] == true) ...[
                            const SizedBox(height: 8),
                            _buildKeyWordsChips(question),
                          ],

                          // 解析內容（如果展開）
                          if (_showExplanation[questionId] == true) ...[
                            const SizedBox(height: 20),
                            _buildRichExplanationSection(question),
                          ],

                          // 功能按鈕（右下角，橫向排列）
                          const SizedBox(height: 16),
                          _buildBottomActions(questionId),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 構建鎖定卡片（VIP 限制：第 11 題起模糊 + 金色鎖，點擊跳轉訂閱頁）
  Widget _buildLockedCard(WrongQuestionEntry entry, int index, int total) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const SubscriptionPage(),
          ),
        );
      },
      child: ClipRRect(
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
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLeftGutter(
                          index, entry.question.answer, entry.wrongCount),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.question.getDisplayQuestionText(
                                defaultText:
                                    AppStrings.get('question_content_missing'),
                              ),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                                color: Color(0xFF0D131B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      const SizedBox(width: 40), // 占位，對齊右欄
                    ],
                  ),
                ),
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        color: Colors.white.withOpacity(0.35),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.lock,
                          size: 52,
                          color: Color(0xFFD4AF37),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 構建左欄（題號 + 正確答案圓圈，極簡版）
  /// 邏輯：只顯示正確答案（V 或 F），題號在圓圈上方
  Widget _buildLeftGutter(int index, bool correctAnswer, int wrongCount) {
    // 根據正確答案決定顯示 V 還是 F
    final label = correctAnswer ? 'V' : 'F';

    return SizedBox(
      width: 46,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 題號（灰色，小字號，與右側題目第一行中心對齊）
          Padding(
            padding: const EdgeInsets.only(top: 6), // 略微下移，避免與上方內容貼合
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

          // 正確答案圓圈（弱化視覺權重）
          _buildAnswerCircle(
            label: label,
            isCorrect: true, // 始終是正確答案，顯示綠色
          ),

          // 錯誤次數標籤（在圓圈下方，動態顏色Chip）
          const SizedBox(height: 6),
          _buildErrorCountChip(wrongCount),
        ],
      ),
    );
  }

  /// 構建答案圓圈（V 或 F，弱化視覺權重版）
  /// 邏輯：只顯示正確答案，使用極細邊框和淺色背景
  Widget _buildAnswerCircle({
    required String label,
    required bool isCorrect, // 是否為正確答案（始終為 true）
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.green.withOpacity(0.1), // 極淺綠色背景
          border: Border.all(
            color: Colors.green[300]!, // 淺綠色邊框
            width: 1.0, // 極細邊框
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600, // 略微減輕字重
              fontFeatures: const [
                FontFeature.tabularFigures()
              ], // Monospace 效果
              color: Colors.green[700]!, // 深綠色文字（而非鮮綠色）
            ),
          ),
        ),
      ),
    );
  }

  /// 獲取錯誤次數標籤的顏色配置
  /// 根據錯誤次數返回對應的文字顏色和背景顏色
  Map<String, Color> _getMistakeColor(int count) {
    if (count <= 2) {
      // 輕度（1-2次）：中性色
      return {
        'text': Colors.grey[600]!,
        'background': Colors.grey[100]!,
        'border': Colors.grey[200]!,
      };
    } else if (count <= 4) {
      // 中度（3-4次）：警示色
      return {
        'text': Colors.orange[700]!,
        'background': Colors.orange[50]!,
        'border': Colors.orange[200]!,
      };
    } else {
      // 重度（5次及以上）：危險色
      return {
        'text': Colors.red[700]!,
        'background': Colors.red[50]!,
        'border': Colors.red[200]!,
      };
    }
  }

  /// 構建錯誤次數標籤（動態顏色，水平排列）
  Widget _buildErrorCountChip(int wrongCount) {
    final colors = _getMistakeColor(wrongCount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colors['background'],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors['border']!,
          width: 0.5,
        ),
      ),
      child: Center(
        child: Text(
          AppStrings.get('error_times').replaceAll('{count}', '$wrongCount'),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: colors['text'],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// 構建底部功能按鈕（右下角，橫向排列，帶背景圓圈）
  Widget _buildBottomActions(String questionId) {
    return FutureBuilder<bool>(
      future: _isFavorite(questionId),
      builder: (context, snapshot) {
        final isFavorite = snapshot.data ?? false;
        final isTranslationActive = _showTranslation[questionId] == true;
        final isExplanationActive = _showExplanation[questionId] == true;

        return Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 收藏按鈕（帶背景圓圈，激活時變紅色）
              GestureDetector(
                onTap: () => _toggleFavorite(questionId),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100]!.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 16,
                    color: isFavorite ? Colors.red[400] : Colors.grey[400],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 解析按鈕（帶背景圓圈，激活時變藍色；展開前做限額檢查與計次）
              GestureDetector(
                onTap: () async {
                  await _onExplanationIconTap(questionId);
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100]!.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isExplanationActive
                        ? Icons.menu_book
                        : Icons.menu_book_outlined,
                    size: 16,
                    color: isExplanationActive
                        ? const Color(0xFF137FEC) // 激活時變藍色（primaryColor）
                        : Colors.grey[400],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 翻譯按鈕（帶背景圓圈，激活時變藍色）
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
                        ? Colors.grey[300] // 禁用狀態
                        : (isTranslationActive
                            ? const Color(0xFF137FEC) // 激活時變藍色（primaryColor）
                            : Colors.grey[400]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 移除按鈕（帶背景圓圈，淡灰色）
              GestureDetector(
                onTap: () => _showRemoveConfirmationDialog(questionId),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100]!.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 構建題目圖片（優化版：100px高度，12px圓角，帶放大鏡圖標）
  Widget _buildQuestionImage(String imagePath) {
    return GestureDetector(
      onTap: () => _showImagePreview(imagePath),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // 圖片主體
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildImageWidget(imagePath),
          ),
          // 放大鏡圖標（右下角，半透明，縮小15%，添加白色邊框）
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(3.4), // 縮小15%（4 * 0.85 ≈ 3.4）
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius:
                    BorderRadius.circular(5.1), // 縮小15%（6 * 0.85 ≈ 5.1）
                border: Border.all(
                  color: Colors.white.withOpacity(0.9),
                  width: 1.0,
                ),
              ),
              child: const Icon(
                Icons.search,
                size: 12, // 縮小15%（14 * 0.85 ≈ 12）
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 構建圖片 Widget（網絡或本地）
  Widget _buildImageWidget(String imagePath) {
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        height: 100,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.shrink();
        },
      );
    } else {
      String assetPath = imagePath;
      if (assetPath.startsWith('/')) {
        assetPath = assetPath.substring(1);
      }
      if (assetPath.startsWith('img_sign/')) {
        assetPath = 'images/$assetPath';
      }
      return Image.asset(
        assetPath,
        height: 100,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.shrink();
        },
      );
    }
  }

  /// 顯示圖片預覽（點擊小圖查看大圖）
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
              // 關閉按鈕（右上角）
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
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
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

  /// 構建大圖顯示
  Widget _buildLargeImage(String imagePath) {
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image_not_supported,
                    size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  AppStrings.get('failed_to_load'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        },
      );
    } else {
      String assetPath = imagePath;
      if (assetPath.startsWith('/')) {
        assetPath = assetPath.substring(1);
      }
      if (assetPath.startsWith('img_sign/')) {
        assetPath = 'images/$assetPath';
      }
      return Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image_not_supported,
                    size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  AppStrings.get('failed_to_load'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  /// 構建關鍵詞標籤（優化版：使用Wrap，支持長單詞完整顯示）
  Widget _buildKeyWordsChips(Question question) {
    final keywords = question.getKeyWords(_currentLanguage);

    if (keywords.isEmpty) {
      return const SizedBox.shrink();
    }

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
            color: Colors.grey[100], // 極淺灰色背景
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey[200]!, // 極淡邊框
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 意大利语单词（不限制宽度，允许完整显示）
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
                Text(
                  '•',
                  style: TextStyle(fontSize: 9, color: Colors.grey[400]),
                ),
                const SizedBox(width: 4),
                // 翻译文本（不限制宽度，允许完整显示）
                Text(
                  translation,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 構建精美解析區塊（JSON 解析 + 詳細說明 / 考點總結 / 學習小貼士）
  /// 結構參考練習模式的解析底部彈窗，但以內嵌卡片方式展示
  Widget _buildRichExplanationSection(Question question) {
    final explanationText = question.getExplanationText(_currentLanguage) ??
        question.getExplanationText('it') ??
        AppStrings.getWithLanguage(
            _currentLanguage, 'explanation_missing_short');

    Map<String, dynamic>? parsedData;
    bool isJsonFormat = false;

    try {
      final decoded = jsonDecode(explanationText);
      if (decoded is Map<String, dynamic> &&
          (decoded.containsKey('detailed_description') ||
              decoded.containsKey('key_points') ||
              decoded.containsKey('study_tip'))) {
        parsedData = decoded;
        isJsonFormat = true;
      }
    } catch (_) {
      // 解析失敗時回退到普通文本模式
    }

    final String detailedDescription;
    final List<Map<String, String>>? keyPoints;
    final String? studyTip;

    if (isJsonFormat && parsedData != null) {
      detailedDescription =
          parsedData['detailed_description'] as String? ?? explanationText;
      final keyPointsRaw = parsedData['key_points'] as List?;
      keyPoints = keyPointsRaw
          ?.map((item) {
            if (item is Map) {
              return {
                'title': item['title']?.toString() ?? '',
                'content': item['content']?.toString() ?? '',
              };
            }
            return {'title': '', 'content': ''};
          })
          .toList()
          .cast<Map<String, String>>();
      studyTip = parsedData['study_tip'] as String?;
    } else {
      detailedDescription = explanationText;
      keyPoints = null;
      studyTip = null;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue[100]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 詳細說明標題
          Text(
            AppStrings.get('detail_description_title'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          // 詳細說明內容
          Text(
            detailedDescription,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF1D1D1F),
            ),
          ),
          if (isJsonFormat && keyPoints != null && keyPoints.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              AppStrings.get('key_points_title'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            ...keyPoints.map((point) {
              final title = point['title'] ?? '';
              final content = point['content'] ?? '';
              if (title.isEmpty && content.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 6, right: 10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF137FEC),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Color(0xFF1D1D1F),
                          ),
                          children: [
                            TextSpan(
                              text: '$title：',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: content,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (isJsonFormat && studyTip != null && studyTip.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue[200]!,
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: Colors.blue[700],
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      studyTip,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 鎖定區域唯一升級橫幅：提示剩餘錯題數，提供「立即解鎖」CTA
  Widget _buildUnlockBanner({required int hiddenCount}) {
    if (hiddenCount <= 0) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withOpacity(0.9),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFFE6A7),
                      Color(0xFFF4D03F),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.lock,
                  size: 18,
                  color: Color(0xFF7C5B07),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${AppStrings.get('hidden_mistakes_banner_prefix')}$hiddenCount${AppStrings.get('hidden_mistakes_banner_suffix')}',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Color(0xFF1F2933),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 34,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SubscriptionPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    backgroundColor: const Color(0xFF137FEC),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    AppStrings.get('unlock_now'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MistakeReviewPracticeScreen extends StatefulWidget {
  const _MistakeReviewPracticeScreen({
    required this.entry,
    required this.currentLanguage,
    required this.userId,
  });

  final WrongQuestionEntry entry;
  final String currentLanguage;
  final String userId;

  @override
  State<_MistakeReviewPracticeScreen> createState() =>
      _MistakeReviewPracticeScreenState();
}

class _MistakeReviewPracticeScreenState
    extends State<_MistakeReviewPracticeScreen> {
  bool _hasAnswered = false;

  Future<void> _onAnswerSelected(bool selectedAnswer) async {
    if (_hasAnswered) return;
    _hasAnswered = true;

    final question = widget.entry.question;
    final isCorrect = selectedAnswer == question.answer;

    // 🔄 使用統一的 updateQuestionProgress 方法（會自動減少 wrong_count）
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    await userStateProvider.updateQuestionProgress(question.id, isCorrect);

    if (!mounted) return;

    // 獲取更新後的 wrong_count
    final wrongQuestions = await DatabaseService.getWrongQuestions(
      widget.userId,
      lang: 'it',
    );
    if (!mounted) return;

    final updatedEntry = wrongQuestions.firstWhere(
      (e) => e.question.id == question.id,
      orElse: () => WrongQuestionEntry(question: question, wrongCount: 0),
    );
    final newCount = updatedEntry.wrongCount;

    if (isCorrect) {
      // 如果 wrong_count 減到 0，顯示特殊反饋
      if (newCount == 0) {
        // 輕微震動反饋
        HapticFeedback.mediumImpact();

        // 顯示成功提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(AppStrings.get('mistake_eliminated')),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppStrings.get('mistake_reduced_prefix')}$newCount${AppStrings.get('mistake_reduced_suffix')}',
            ),
          ),
        );
      }
      Navigator.pop(context, newCount);
    } else {
      await DatabaseService.recordError(
        question.id,
        userId: widget.userId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('mistake_retry_message'))),
      );
      Navigator.pop(context, widget.entry.wrongCount + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('mistake_review_title')),
      ),
      body: QuestionWidget(
        question: widget.entry.question,
        onAnswerSelected: _onAnswerSelected,
        currentLanguage: widget.currentLanguage,
        isExamMode: false,
        showQuestionCounter: false,
      ),
    );
  }
}
