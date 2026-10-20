import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../config/chapter_config.dart';
import '../config/locale_format.dart';
import '../models/chapter_capability.dart';
import '../providers/user_state_provider.dart';
import '../services/access_policy.dart';
import '../services/database_service.dart';
import 'practice_screen.dart';
import 'subscription_page.dart';

class MasteryReportScreen extends StatefulWidget {
  const MasteryReportScreen({super.key});

  @override
  State<MasteryReportScreen> createState() => _MasteryReportScreenState();
}

class _MasteryReportScreenState extends State<MasteryReportScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  List<ChapterCapability> _chapterCapabilities = [];
  List<Map<String, dynamic>> _mockHistory = [];
  List<Map<String, dynamic>> _dailyGrowth = [];
  bool _showAllCapabilities = false;
  int? _highlightedChapterId;
  int? _chartTouchedSpotIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAfterResume();
    }
  }

  Future<void> _refreshAfterResume() async {
    try {
      await context.read<UserStateProvider>().checkAndResetDailyCounters();
      if (mounted) await _loadData();
    } catch (_) {
      // 前景刷新失敗時保留現有報告，使用者仍可手動重新進入頁面。
    }
  }

  Future<void> _loadData() async {
    try {
      final userState = context.read<UserStateProvider>();
      final userId = userState.effectiveUserId;

      await userState.updateMasteryStats();
      final capabilityStats =
          await DatabaseService.getChapterCapabilityStats(userId: userId);
      final history = await DatabaseService.getMockExamHistory(userId: userId);
      final dailyGrowth =
          await DatabaseService.getDailyGrowth(userId: userId, days: 7);
      await userState.loadPassRatePrediction();
      await userState.loadMockExamImprovement();

      final recent5 = history.take(5).toList().reversed.toList();
      if (!mounted) return;
      setState(() {
        _chapterCapabilities = capabilityStats
            .map(ChapterCapability.fromMap)
            .where((capability) => capability.chapterId > 0)
            .toList();
        _mockHistory = recent5;
        _dailyGrowth = dailyGrowth;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatPercentage(double value) {
    final pct = (value * 100).clamp(0, 100).toStringAsFixed(0);
    return '$pct%';
  }

  String _buildChapterTitle(int chapterId, String lang) {
    final chapter = ChapterConfig.chapters.firstWhere((c) => c.id == chapterId);
    final title = chapter.titleTranslations[lang] ??
        chapter.titleTranslations['zh'] ??
        chapter.titleIt;
    switch (lang) {
      case 'zh':
        return '第 $chapterId 章：$title';
      case 'en':
        return 'Chapter $chapterId: $title';
      case 'ru':
        return 'Глава $chapterId: $title';
      case 'uk':
        return 'Розділ $chapterId: $title';
      case 'ur':
        return 'باب $chapterId: $title';
      case 'pa':
        return 'ਅਧਿਆਇ $chapterId: $title';
      default:
        return '$chapterId. $title';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserStateProvider>();
    final isVip = userState.isVip;
    final currentLang = userState.currentLanguage;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppTheme.pageBackgroundFor(context),
      appBar: AppBar(
        title: Text(
          AppStrings.getWithLanguage(currentLang, 'mastery_report_title'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        backgroundColor: AppTheme.pageBackgroundFor(context),
        elevation: 0,
        // 滾動時不疊加 Material 3 的表面著色，頂欄保持頁面底色。
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        decoration: AppTheme.pageDecorationFor(context),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildOverallGaugeCard(currentLang),
                    const SizedBox(height: 24),
                    _buildWeeklyGrowthSection(currentLang),
                    const SizedBox(height: 24),
                    _buildChapterCapabilitySection(userState, currentLang),
                    const SizedBox(height: 24),
                    _buildVipAnalyticsSection(isVip, currentLang),
                  ],
                ),
              ),
      ),
    );
  }

  int _growthValue(Map<String, dynamic> entry, String key) {
    return (entry[key] as num? ?? 0).toInt();
  }

  List<Map<String, dynamic>> get _lastSevenDaysGrowth {
    final normalized = List<Map<String, dynamic>>.generate(
      7,
      (_) => {
        'date': '',
        'answered': 0,
        'correct': 0,
        'newlyMastered': 0,
        'mistakesResolved': 0,
      },
    );
    final source = _dailyGrowth.length > 7
        ? _dailyGrowth.sublist(_dailyGrowth.length - 7)
        : _dailyGrowth;
    final start = normalized.length - source.length;
    for (var index = 0; index < source.length; index++) {
      normalized[start + index] = source[index];
    }
    return normalized;
  }

  Widget _buildWeeklyGrowthSection(String lang) {
    final primaryColor = AppTheme.primaryFor(context);
    final mutedColor = AppTheme.mutedFor(context);
    final surfaceColor = AppTheme.surfaceFor(context);
    final isRetro = AppTheme.isRetroFor(context);
    final dailyGrowth = _lastSevenDaysGrowth;
    final answered = dailyGrowth.fold<int>(
      0,
      (total, entry) => total + _growthValue(entry, 'answered'),
    );
    final studyDays = dailyGrowth
        .where((entry) => _growthValue(entry, 'answered') > 0)
        .length;
    final newlyMastered = dailyGrowth.fold<int>(
      0,
      (total, entry) => total + _growthValue(entry, 'newlyMastered'),
    );
    final mistakesResolved = dailyGrowth.fold<int>(
      0,
      (total, entry) => total + _growthValue(entry, 'mistakesResolved'),
    );
    final maxAnswered = dailyGrowth.fold<int>(
      0,
      (currentMax, entry) => max(currentMax, _growthValue(entry, 'answered')),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.getWithLanguage(lang, 'growth_week_title'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surfaceColor.withOpacity(isRetro ? 0.98 : 0.94),
            borderRadius:
                isRetro ? BorderRadius.zero : BorderRadius.circular(20),
            border:
                Border.all(color: AppTheme.lineFor(context).withOpacity(0.5)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 66,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: dailyGrowth.map((entry) {
                    final dayAnswered = _growthValue(entry, 'answered');
                    final height = maxAnswered == 0
                        ? 4.0
                        : 4 + (dayAnswered / maxAnswered) * 42;
                    final date = entry['date'] as String? ?? '';
                    final dayLabel =
                        date.length >= 2 ? date.substring(date.length - 2) : '';
                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: 16,
                            height: height,
                            decoration: BoxDecoration(
                              color: dayAnswered > 0
                                  ? primaryColor
                                  : primaryColor.withOpacity(0.14),
                              borderRadius: isRetro
                                  ? BorderRadius.zero
                                  : BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dayLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: mutedColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (answered == 0) ...[
                const SizedBox(height: 12),
                Text(
                  AppStrings.getWithLanguage(lang, 'growth_no_activity'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: mutedColor),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildGrowthMetric(
                    '$studyDays / 7',
                    AppStrings.getWithLanguage(lang, 'growth_study_days'),
                  ),
                  _buildGrowthMetric(
                    '$answered',
                    AppStrings.getWithLanguage(lang, 'growth_answered'),
                  ),
                  _buildGrowthMetric(
                    '$newlyMastered',
                    AppStrings.getWithLanguage(lang, 'growth_newly_mastered'),
                  ),
                  _buildGrowthMetric(
                    '$mistakesResolved',
                    AppStrings.getWithLanguage(
                        lang, 'growth_mistakes_resolved'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrowthMetric(String value, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    final mutedColor = AppTheme.mutedFor(context);
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: mutedColor),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallGaugeCard(String lang) {
    final userState = context.watch<UserStateProvider>();
    final passRate = userState.passRatePrediction;
    final isInsufficientData = passRate < 0;
    final isZeroRate = passRate == 0;
    final displayValue = passRate < 0 ? 0.0 : passRate.clamp(0.0, 1.0);
    final isRetro = AppTheme.isRetroFor(context);
    final surfaceColor = AppTheme.surfaceFor(context);
    final mutedColor = AppTheme.mutedFor(context);
    final primaryColor = AppTheme.primaryFor(context);

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor.withOpacity(isRetro ? 0.98 : 0.86),
        borderRadius: isRetro
            ? BorderRadius.zero
            : BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.lineFor(context).withOpacity(0.5)),
        boxShadow: AppTheme.cardShadowFor(context),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 180,
            height: 90,
            child: CustomPaint(
              painter: _SemiGaugePainter(
                percentage: displayValue,
                backgroundColor: AppTheme.lineFor(context).withOpacity(0.45),
                progressColor: primaryColor,
              ),
              child: Center(
                child: Text(
                  isInsufficientData
                      ? '--'
                      : isZeroRate
                          ? '0%'
                          : _formatPercentage(displayValue),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: isInsufficientData || isZeroRate
                        ? mutedColor
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isInsufficientData
                ? AppStrings.getWithLanguage(lang, 'need_more_data')
                : isZeroRate
                    ? AppStrings.getWithLanguage(lang, 'no_exam_data')
                    : AppStrings.getWithLanguage(
                        lang, 'pass_rate_prediction_subtitle'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: mutedColor,
            ),
          ),
          if (!isInsufficientData &&
              !isZeroRate &&
              userState.isPassRatePredictionLowAccuracy)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                AppStrings.getWithLanguage(lang, 'prediction_accuracy_low'),
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.warningTextFor(context),
                ),
              ),
            ),
          _buildImprovementChip(lang),
          if (isInsufficientData || isZeroRate)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoftFor(context),
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(999),
                ),
                child: Text(
                  AppStrings.getWithLanguage(lang, 'collecting_study_data'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 较昨天提升/下降标签：passRate <= 0（含 -1 数据不足）或提升为 0 时必须隐藏
  Widget _buildImprovementChip(String lang) {
    final userState = context.watch<UserStateProvider>();
    if (userState.passRatePrediction <= 0) return const SizedBox.shrink();
    final improvement = userState.mockExamImprovement;
    if (improvement == null || improvement == 0) return const SizedBox.shrink();
    final isUp = improvement > 0;
    final pct = (improvement.abs() * 100).round();
    final statusColor =
        isUp ? AppTheme.successFor(context) : AppTheme.dangerFor(context);
    final statusBackground = isUp
        ? AppTheme.successSoftFor(context)
        : AppTheme.dangerSoftFor(context);
    final isRetro = AppTheme.isRetroFor(context);
    final label =
        '${isUp ? AppStrings.getWithLanguage(lang, 'improvement_vs_yesterday_up') : AppStrings.getWithLanguage(lang, 'improvement_vs_yesterday_down')} $pct%';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: statusBackground,
          borderRadius:
              isRetro ? BorderRadius.zero : BorderRadius.circular(999),
          border: Border.all(color: statusColor.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isUp ? Icons.trending_up : Icons.trending_down,
              size: 16,
              color: statusColor,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterCapabilitySection(
    UserStateProvider userState,
    String lang,
  ) {
    final capabilities = [..._chapterCapabilities]..sort((a, b) {
        final aAccessPriority = userState.isChapterLocked(a.chapterId) ? 1 : 0;
        final bAccessPriority = userState.isChapterLocked(b.chapterId) ? 1 : 0;
        final accessComparison = aAccessPriority.compareTo(bAccessPriority);
        if (accessComparison != 0) return accessComparison;

        final stateComparison = _capabilityPriority(a.state)
            .compareTo(_capabilityPriority(b.state));
        if (stateComparison != 0) return stateComparison;

        if (a.state == ChapterCapabilityState.needsAttention) {
          final mistakeComparison =
              b.mistakeDensity.compareTo(a.mistakeDensity);
          if (mistakeComparison != 0) return mistakeComparison;
        }
        return a.chapterId.compareTo(b.chapterId);
      });
    var visibleCapabilities =
        _showAllCapabilities ? capabilities : capabilities.take(5).toList();
    if (!_showAllCapabilities &&
        _highlightedChapterId != null &&
        !visibleCapabilities.any(
          (capability) => capability.chapterId == _highlightedChapterId,
        )) {
      final highlighted = capabilities.where(
        (capability) => capability.chapterId == _highlightedChapterId,
      );
      if (highlighted.isNotEmpty) {
        visibleCapabilities = [
          ...capabilities.take(4),
          highlighted.first,
        ];
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.getWithLanguage(lang, 'chapter_capability_title'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (capabilities.length > 5)
              TextButton(
                onPressed: () {
                  setState(() => _showAllCapabilities = !_showAllCapabilities);
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryFor(context),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  AppStrings.getWithLanguage(
                    lang,
                    _showAllCapabilities
                        ? 'chapter_capability_show_priority'
                        : 'chapter_capability_show_all',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ...visibleCapabilities.map(
          (capability) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildCapabilityCard(capability, userState, lang),
          ),
        ),
      ],
    );
  }

  Widget _buildCapabilityCard(
    ChapterCapability capability,
    UserStateProvider userState,
    String lang,
  ) {
    final color = _capabilityColor(capability.state);
    final isLocked = userState.isChapterLocked(capability.chapterId);
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final cardColor = AppTheme.surfaceFor(context);
    final mutedColor = AppTheme.mutedFor(context);
    final stats = AppStrings.getWithLanguage(lang, 'chapter_capability_stats')
        .replaceAll('{practiced}', '${capability.practiced}')
        .replaceAll('{total}', '${capability.total}')
        .replaceAll('{mastered}', '${capability.mastered}')
        .replaceAll('{mistakes}', '${capability.mistakes}');

    final isHighlighted = _highlightedChapterId == capability.chapterId;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHighlighted
            ? color.withOpacity(0.08)
            : cardColor.withOpacity(isRetro ? 0.98 : 0.92),
        borderRadius: isRetro
            ? BorderRadius.zero
            : BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: color.withOpacity(isHighlighted ? 0.8 : 0.2),
          width: isHighlighted ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: isRetro ? BoxShape.rectangle : BoxShape.circle,
                ),
                child: Icon(
                  _capabilityIcon(capability.state),
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _buildChapterTitle(capability.chapterId, lang),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(999),
                ),
                child: Text(
                  _capabilityStateLabel(capability.state, lang),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius:
                isRetro ? BorderRadius.zero : BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: capability.coverageRatio.clamp(0, 1),
              backgroundColor: AppTheme.lineFor(context).withOpacity(0.65),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            stats,
            style: TextStyle(
              fontSize: 11,
              color: mutedColor,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _startCapabilityPractice(capability),
              icon: Icon(isLocked ? Icons.lock_outline : Icons.bolt, size: 17),
              label: Text(_capabilityActionLabel(capability.state, lang)),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: color.withOpacity(0.12),
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _capabilityPriority(ChapterCapabilityState state) {
    switch (state) {
      case ChapterCapabilityState.needsAttention:
        return 0;
      case ChapterCapabilityState.learning:
        return 1;
      case ChapterCapabilityState.notStarted:
        return 2;
      case ChapterCapabilityState.stable:
        return 3;
    }
  }

  Color _capabilityColor(ChapterCapabilityState state) {
    switch (state) {
      case ChapterCapabilityState.notStarted:
        return AppTheme.mutedFor(context);
      case ChapterCapabilityState.learning:
        return AppTheme.primaryFor(context);
      case ChapterCapabilityState.needsAttention:
        // 道路主題用標誌黃系提示「需要加強」，避免整頁粉紅色的壓迫感。
        return AppTheme.usesRoadPalette && !AppTheme.isRetroFor(context)
            ? AppTheme.warningTextFor(context)
            : AppTheme.dangerFor(context);
      case ChapterCapabilityState.stable:
        return AppTheme.successFor(context);
    }
  }

  IconData _capabilityIcon(ChapterCapabilityState state) {
    switch (state) {
      case ChapterCapabilityState.notStarted:
        return Icons.radio_button_unchecked;
      case ChapterCapabilityState.learning:
        return Icons.school_outlined;
      case ChapterCapabilityState.needsAttention:
        return Icons.priority_high;
      case ChapterCapabilityState.stable:
        return Icons.check;
    }
  }

  String _capabilityStateLabel(ChapterCapabilityState state, String lang) {
    switch (state) {
      case ChapterCapabilityState.notStarted:
        return AppStrings.getWithLanguage(
          lang,
          'chapter_capability_not_started',
        );
      case ChapterCapabilityState.learning:
        return AppStrings.getWithLanguage(lang, 'chapter_capability_learning');
      case ChapterCapabilityState.needsAttention:
        return AppStrings.getWithLanguage(
          lang,
          'chapter_capability_needs_attention',
        );
      case ChapterCapabilityState.stable:
        return AppStrings.getWithLanguage(lang, 'chapter_capability_stable');
    }
  }

  String _capabilityActionLabel(ChapterCapabilityState state, String lang) {
    switch (state) {
      case ChapterCapabilityState.notStarted:
        return AppStrings.getWithLanguage(lang, 'chapter_capability_start');
      case ChapterCapabilityState.stable:
        return AppStrings.getWithLanguage(lang, 'chapter_capability_review');
      case ChapterCapabilityState.learning:
      case ChapterCapabilityState.needsAttention:
        return AppStrings.getWithLanguage(
          lang,
          'chapter_capability_strengthen',
        );
    }
  }

  Future<void> _startCapabilityPractice(ChapterCapability capability) async {
    final userState = context.read<UserStateProvider>();
    await userState.checkAndResetDailyCounters();
    if (!mounted) return;

    if (userState.isChapterLocked(capability.chapterId)) {
      await _showCapabilityAccessPrompt(
        title: AppStrings.getWithLanguage(
          userState.currentLanguage,
          'chapter_locked_title',
        ),
        message: AppStrings.getWithLanguage(
          userState.currentLanguage,
          'chapter_locked_message',
        ),
      );
      return;
    }

    if (!userState.canPractice()) {
      await _showCapabilityAccessPrompt(
        title: AppStrings.getWithLanguage(
          userState.currentLanguage,
          'quiz_limit_reached',
        ),
        message: AppStrings.getWithLanguage(
          userState.currentLanguage,
          'quiz_limit_message',
        ),
      );
      return;
    }

    final questionLimit = userState.isVip
        ? 10
        : min(
            10,
            AccessPolicy.freeDailyQuizLimit - userState.dailyQuizCount,
          );
    final strengthenedChapterId = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => PracticeScreen(
          chapterId: capability.chapterId,
          skipMastered: capability.state != ChapterCapabilityState.stable,
          strengtheningStart: capability,
          strengtheningQuestionLimit: questionLimit,
        ),
      ),
    );
    if (!mounted) return;
    await userState.syncProgressToCloudIfVip();
    if (!mounted) return;
    await _loadData();
    if (!mounted || strengthenedChapterId == null) return;
    setState(() => _highlightedChapterId = strengthenedChapterId);
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && _highlightedChapterId == strengthenedChapterId) {
        setState(() => _highlightedChapterId = null);
      }
    });
  }

  Future<void> _showCapabilityAccessPrompt({
    required String title,
    required String message,
  }) async {
    final lang = context.read<UserStateProvider>().currentLanguage;
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = AppTheme.primaryFor(context);
    final shouldSubscribe = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock, color: primaryColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 16,
            color: colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.getWithLanguage(lang, 'return_home')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: colorScheme.onPrimary,
            ),
            child: Text(
              AppStrings.getWithLanguage(lang, 'go_subscribe_unlock'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || shouldSubscribe != true) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SubscriptionPage()),
    );
  }

  /// 模擬考錯誤趨勢區塊（已取消 VIP 鎖定，所有用戶可見；底部按鈕跳轉訂閱頁）
  Widget _buildVipAnalyticsSection(bool isVip, String lang) {
    const chartHeight = 200.0;
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final primaryColor = AppTheme.primaryFor(context);
    final surfaceColor = AppTheme.surfaceFor(context);

    final titleSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            AppStrings.getWithLanguage(lang, 'mock_exam_trend_title'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.getWithLanguage(lang, 'recent_5_trends'),
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.mutedFor(context),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleSection,
        Container(
          decoration: BoxDecoration(
            color: surfaceColor.withOpacity(isRetro ? 0.98 : 0.86),
            borderRadius: isRetro
                ? BorderRadius.zero
                : BorderRadius.circular(AppTheme.radiusXl),
            border:
                Border.all(color: AppTheme.lineFor(context).withOpacity(0.5)),
          ),
          padding: const EdgeInsets.all(16),
          height: chartHeight,
          child: _buildMockHistoryChart(lang),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SubscriptionPage(),
                  ),
                );
              },
              borderRadius:
                  isRetro ? BorderRadius.zero : BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius:
                      isRetro ? BorderRadius.zero : BorderRadius.circular(999),
                  boxShadow: AppTheme.cardShadowFor(context),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        AppStrings.getWithLanguage(lang, 'ai_advice_cta'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimary,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: colorScheme.onPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const double _passThresholdY = 3.0; // B 照最高错误上限

  String _formatChartDate(dynamic timestamp) {
    if (timestamp == null) return '';
    final sec = timestamp is int
        ? timestamp
        : (timestamp is num ? timestamp.toInt() : 0);
    if (sec <= 0) return '';
    final ms = sec > 9999999999 ? sec : sec * 1000;
    final dt = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    return LocaleFormat.shortDate(AppStrings.getLanguage(), dt);
  }

  Widget _buildMockHistoryChart(String lang) {
    final primaryColor = AppTheme.primaryFor(context);
    final mutedColor = AppTheme.mutedFor(context);
    final surfaceColor = AppTheme.surfaceFor(context);
    final successColor = AppTheme.successFor(context);
    final dangerColor = AppTheme.dangerFor(context);
    final isRetro = AppTheme.isRetroFor(context);
    if (_mockHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 42,
              color: primaryColor.withOpacity(0.3),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.getWithLanguage(lang, 'trend_chart_locked_desc'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: mutedColor,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    final wrongCounts = <int>[];
    final spots = <FlSpot>[];
    for (var i = 0; i < _mockHistory.length; i++) {
      final item = _mockHistory[i];
      final wrong = (item['wrong'] as int?) ?? 0;
      wrongCounts.add(wrong);
      spots.add(FlSpot(i.toDouble(), wrong.toDouble()));
    }
    if (spots.length == 1) {
      spots.add(FlSpot(spots[0].x + 0.5, spots[0].y));
    }

    final n = wrongCounts.length;
    const chartMinX = -0.2;
    final chartMaxX = n <= 1 ? 0.8 : n - 0.8;

    final maxVal =
        wrongCounts.isEmpty ? 0 : wrongCounts.reduce((a, b) => a > b ? a : b);
    const chartMinY = 0.0;
    final chartMaxY = (maxVal > 10 ? maxVal : 10).toDouble() + 5.0;

    // 折線表示錯題數，升高不是好事：線用中性色，及格與否只由圓點顏色表達。
    final lineColor = AppTheme.usesRoadPalette && !isRetro
        ? AppTheme.inkFor(context).withOpacity(0.55)
        : primaryColor;
    final barData = LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.3,
      barWidth: 3,
      color: lineColor,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bd, index) {
          final isPass = spot.y <= _passThresholdY;
          return FlDotCirclePainter(
            radius: 5,
            color: surfaceColor,
            strokeColor: isPass ? primaryColor : dangerColor,
            strokeWidth: 2.5,
          );
        },
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withOpacity(0.25),
            lineColor.withOpacity(0.06),
            Colors.transparent,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 8, top: 8, bottom: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chartH = constraints.maxHeight;
          const bottomReserved = 22.0;
          final plotH = chartH - bottomReserved;
          final lineY = plotH * (1 - _passThresholdY / chartMaxY);
          const leftReserved = 45.0;
          const oneCharWidth = 10.0;
          const passLabelWidth = 32.0; // 「及格线」约 3 字宽
          const passLabelRight = 2.0;
          final gapStartX = constraints.maxWidth -
              passLabelRight -
              passLabelWidth -
              oneCharWidth;
          final passLineColor = successColor.withOpacity(0.5);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size(constraints.maxWidth, chartH),
                painter: _ChartGridLinesPainter(
                  passLineY: lineY,
                  bottomY: plotH,
                  leftX: leftReserved,
                  gapStartX: gapStartX,
                  passLineColor: passLineColor,
                  bottomLineColor: mutedColor.withOpacity(0.25),
                  strokeWidth: 1.5,
                  dashLength: 4,
                  gapLength: 4,
                ),
              ),
              LineChart(
                LineChartData(
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    drawHorizontalLine: false,
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 45,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final v = value.toInt();
                          if (v != value) {
                            return const SizedBox.shrink();
                          }
                          const allowedTicks = [0, 3, 10, 20, 30];
                          if (!allowedTicks.contains(v) ||
                              v < chartMinY ||
                              v > chartMaxY) {
                            return const SizedBox.shrink();
                          }
                          final isPassTick = (v == 3);
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              '$v',
                              style: TextStyle(
                                fontSize: 10,
                                color: isPassTick
                                    ? passLineColor
                                    : mutedColor.withOpacity(0.5),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          if (n == 0) {
                            return const SizedBox.shrink();
                          }
                          final vi = value.round();
                          if (vi != value || vi < 0 || vi > n - 1) {
                            return const SizedBox.shrink();
                          }
                          final ts = vi < _mockHistory.length
                              ? _mockHistory[vi]['timestamp']
                              : null;
                          final label = _formatChartDate(ts);
                          // 同一天多次考試只在第一次下方標日期，避免重複。
                          final previousLabel = vi > 0 &&
                                  vi - 1 < _mockHistory.length
                              ? _formatChartDate(
                                  _mockHistory[vi - 1]['timestamp'])
                              : null;
                          if (label.isNotEmpty && label == previousLabel) {
                            return const SizedBox.shrink();
                          }
                          final displayLabel = label.isEmpty
                              ? '${AppStrings.getWithLanguage(lang, 'mock_exam_nth_prefix')}${vi + 1}'
                              : label;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              displayLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: mutedColor.withOpacity(0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      left: BorderSide(color: mutedColor.withOpacity(0.2)),
                      bottom: BorderSide(color: mutedColor.withOpacity(0.2)),
                    ),
                  ),
                  minX: chartMinX,
                  maxX: chartMaxX,
                  minY: chartMinY,
                  maxY: chartMaxY,
                  lineTouchData: LineTouchData(
                    touchCallback: (event, response) {
                      if (response?.lineBarSpots != null &&
                          response!.lineBarSpots!.isNotEmpty) {
                        setState(() => _chartTouchedSpotIndex =
                            response.lineBarSpots!.first.spotIndex);
                      } else {
                        setState(() => _chartTouchedSpotIndex = null);
                      }
                    },
                    handleBuiltInTouches: true,
                    getTouchedSpotIndicator: (barData, spotIndexes) =>
                        spotIndexes.map((i) {
                      final isPass = i < barData.spots.length &&
                          barData.spots[i].y <= _passThresholdY;
                      return TouchedSpotIndicatorData(
                        const FlLine(color: Colors.transparent),
                        FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bd, idx) =>
                              FlDotCirclePainter(
                            radius: 5,
                            color: surfaceColor,
                            strokeColor: isPass ? primaryColor : dangerColor,
                            strokeWidth: 2.5,
                          ),
                        ),
                      );
                    }).toList(),
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((s) {
                          final dataIndex = s.spotIndex < n
                              ? s.spotIndex
                              : (n > 0 ? n - 1 : 0);
                          final wrong = wrongCounts[dataIndex];
                          return LineTooltipItem(
                            '$wrong',
                            TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          );
                        }).toList();
                      },
                      tooltipRoundedRadius: isRetro ? 0 : 6,
                      tooltipPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                  ),
                  showingTooltipIndicators: _chartTouchedSpotIndex != null &&
                          _chartTouchedSpotIndex! < spots.length
                      ? [
                          ShowingTooltipIndicators(
                            [
                              LineBarSpot(
                                barData,
                                0,
                                spots[_chartTouchedSpotIndex!],
                              ),
                            ],
                          ),
                        ]
                      : [],
                  lineBarsData: [barData],
                ),
                duration: const Duration(milliseconds: 150),
              ),
              // 及格线标注：虚线正对文字纵向中点，右对齐
              Positioned(
                top: lineY - 6,
                left: leftReserved,
                right: 2,
                child: Text(
                  AppStrings.getWithLanguage(lang, 'pass_line_label'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: passLineColor,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 仅绘制 y=0 底线与 y=3 及格线（虚线，文字处断开）
class _ChartGridLinesPainter extends CustomPainter {
  final double passLineY;
  final double bottomY;
  final double leftX;
  final double gapStartX;
  final Color passLineColor;
  final Color bottomLineColor;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  _ChartGridLinesPainter({
    required this.passLineY,
    required this.bottomY,
    required this.leftX,
    required this.gapStartX,
    required this.passLineColor,
    required this.bottomLineColor,
    this.strokeWidth = 1.5,
    this.dashLength = 4,
    this.gapLength = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    stroke.color = bottomLineColor;
    canvas.drawLine(
        Offset(leftX, bottomY), Offset(size.width, bottomY), stroke);

    if (gapStartX > leftX) {
      stroke.color = passLineColor;
      final endX = gapStartX.clamp(leftX, size.width);
      double x = leftX;
      while (x < endX) {
        final dashEnd = (x + dashLength).clamp(x, endX);
        canvas.drawLine(
            Offset(x, passLineY), Offset(dashEnd, passLineY), stroke);
        x += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartGridLinesPainter old) =>
      old.passLineY != passLineY ||
      old.bottomY != bottomY ||
      old.leftX != leftX ||
      old.gapStartX != gapStartX ||
      old.passLineColor != passLineColor ||
      old.bottomLineColor != bottomLineColor;
}

/// 半圓儀表盤繪製：漸變弧線、圓角端、極淡灰底
class _SemiGaugePainter extends CustomPainter {
  final double percentage; // 0.0 - 1.0
  final Color backgroundColor;
  final Color progressColor;

  _SemiGaugePainter({
    required this.percentage,
    required this.backgroundColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, pi, pi, false, backgroundPaint);

    if (percentage > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round;

      final sweepAngle = pi * percentage.clamp(0.0, 1.0);
      canvas.drawArc(rect, pi, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SemiGaugePainter oldDelegate) {
    return oldDelegate.percentage != percentage ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressColor != progressColor;
  }
}
