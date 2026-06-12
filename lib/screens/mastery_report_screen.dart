import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_strings.dart';
import '../config/chapter_config.dart';
import '../providers/user_state_provider.dart';
import '../services/database_service.dart';
import '../widgets/empty_state_view.dart';
import 'chapter_selection_screen.dart';
import 'mistake_review_screen.dart';
import 'subscription_page.dart';
import 'practice_screen.dart';

class MasteryReportScreen extends StatefulWidget {
  const MasteryReportScreen({super.key});

  @override
  State<MasteryReportScreen> createState() => _MasteryReportScreenState();
}

class _MasteryReportScreenState extends State<MasteryReportScreen> {
  bool _isLoading = true;
  List<Map<String, int>> _topWeakChapters = [];
  List<Map<String, dynamic>> _mockHistory = [];
  int? _chartTouchedSpotIndex;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userState = context.read<UserStateProvider>();
      final userId = userState.effectiveUserId;

      await userState.updateMasteryStats();
      final weakChapters =
          await DatabaseService.getTopWeakChapters(userId: userId, limit: 3);
      final history = await DatabaseService.getMockExamHistory(userId: userId);
      await userState.loadPassRatePrediction();
      await userState.loadMockExamImprovement();

      final recent5 = history.take(5).toList().reversed.toList();
      setState(() {
        _topWeakChapters = weakChapters;
        _mockHistory = recent5;
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
    final hasAnyData = userState.attemptedCount > 0 ||
        _mockHistory.isNotEmpty ||
        _topWeakChapters.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          AppStrings.getWithLanguage(currentLang, 'mastery_report_title'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: Color(0xFF475569),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE8F4FC),
              Color(0xFFF5FAFE),
              Color(0xFFFDFCFB),
              Color(0xFFFFF9F5),
            ],
            stops: [0.0, 0.35, 0.7, 1.0],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : hasAnyData
                ? SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildOverallGaugeCard(currentLang),
                        const SizedBox(height: 24),
                        _buildWeakChaptersSection(currentLang),
                        const SizedBox(height: 24),
                        _buildVipAnalyticsSection(isVip, currentLang),
                      ],
                    ),
                  )
                : _buildEmptyMasteryState(context, currentLang),
      ),
    );
  }

  Widget _buildEmptyMasteryState(BuildContext context, String lang) {
    final userState = context.read<UserStateProvider>();
    return Center(
      child: EmptyStateView(
        icon: Icons.insights_outlined,
        title: AppStrings.getWithLanguage(lang, 'empty_report_title'),
        description:
            AppStrings.getWithLanguage(lang, 'empty_report_description'),
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
              MaterialPageRoute<void>(
                builder: (context) => PracticeScreen(
                  skipMastered: userState.skipMastered,
                ),
              ),
            );
          },
          child: Text(
            AppStrings.getWithLanguage(lang, 'go_practice'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildOverallGaugeCard(String lang) {
    final userState = context.watch<UserStateProvider>();
    final passRate = userState.passRatePrediction;
    final isInsufficientData = passRate < 0;
    final isZeroRate = passRate == 0;
    final displayValue = passRate < 0 ? 0.0 : passRate.clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 180,
            height: 90,
            child: CustomPaint(
              painter: _SemiGaugePainter(percentage: displayValue),
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
                        ? Colors.grey.shade500
                        : const Color(0xFF0F172A),
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
              color: Colors.grey.shade600,
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
                  color: Colors.orange.shade700,
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
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  AppStrings.getWithLanguage(lang, 'collecting_study_data'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D4ED8),
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
    final label =
        '${isUp ? AppStrings.getWithLanguage(lang, 'improvement_vs_yesterday_up') : AppStrings.getWithLanguage(lang, 'improvement_vs_yesterday_down')} $pct%';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isUp
              ? const Color(0xFFD1FAE5)
              : const Color(0xFFFEE2E2).withOpacity(0.9),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: (isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626))
                  .withOpacity(0.2),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isUp ? Icons.trending_up : Icons.trending_down,
              size: 16,
              color: isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeakChaptersSection(String currentLang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                AppStrings.getWithLanguage(currentLang, 'focus_chapters_title'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            if (_topWeakChapters.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const MistakeReviewScreen(initialTabIndex: 0),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF137FEC),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                    AppStrings.getWithLanguage(currentLang, 'mistake_review'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_topWeakChapters.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              AppStrings.getWithLanguage(
                  currentLang, 'no_weak_chapters_placeholder'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          )
        else
          Column(
            children: _topWeakChapters.take(2).map((entry) {
              final index = _topWeakChapters.indexOf(entry);
              final chapterId = entry['chapter'] ?? 0;
              final errors = entry['errors'] ?? 0;
              final title = _buildChapterTitle(chapterId, currentLang);

              final isPrimary = index == 0;
              final icon =
                  isPrimary ? Icons.priority_high : Icons.speed_rounded;
              final iconColor =
                  isPrimary ? const Color(0xFFDC2626) : const Color(0xFFF97316);

              return Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChapterSelectionScreen(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 20,
                            spreadRadius: 0,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isPrimary
                                    ? [
                                        const Color(0xFFFECACA),
                                        const Color(0xFFFEE2E2),
                                      ]
                                    : [
                                        const Color(0xFFFED7AA),
                                        const Color(0xFFFFEDD5),
                                      ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isPrimary
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFFF97316))
                                      .withOpacity(0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(icon, color: iconColor, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${AppStrings.getWithLanguage(currentLang, 'error_count_prefix')}$errors',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: const Color(0xFF137FEC).withOpacity(0.8),
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  /// 模擬考錯誤趨勢區塊（已取消 VIP 鎖定，所有用戶可見；底部按鈕跳轉訂閱頁）
  Widget _buildVipAnalyticsSection(bool isVip, String lang) {
    const chartHeight = 200.0;

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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.getWithLanguage(lang, 'recent_5_trends'),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
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
            color: Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
            ),
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
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        AppStrings.getWithLanguage(lang, 'ai_advice_cta'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: Colors.white,
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
    return '${dt.month}/${dt.day}';
  }

  Widget _buildMockHistoryChart(String lang) {
    if (_mockHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 42,
              color: const Color(0xFF137FEC).withOpacity(0.3),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.getWithLanguage(lang, 'trend_chart_locked_desc'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF),
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

    final barData = LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.3,
      barWidth: 3,
      color: const Color(0xFF137FEC),
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bd, index) {
          final isPass = spot.y <= _passThresholdY;
          return FlDotCirclePainter(
            radius: 5,
            color: Colors.white,
            strokeColor:
                isPass ? const Color(0xFF2563EB) : const Color(0xFFDC2626),
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
            const Color(0xFF1D4ED8).withOpacity(0.35),
            const Color(0xFF137FEC).withOpacity(0.08),
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
          final passLineColor = Colors.green.withOpacity(0.5);

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
                  bottomLineColor: Colors.grey.withOpacity(0.25),
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
                                    : Colors.grey.withOpacity(0.5),
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
                                color: Colors.grey.withOpacity(0.5),
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
                      left: BorderSide(color: Colors.grey.withOpacity(0.2)),
                      bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
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
                            color: Colors.white,
                            strokeColor: isPass
                                ? const Color(0xFF2563EB)
                                : const Color(0xFFDC2626),
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
                            const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          );
                        }).toList();
                      },
                      tooltipRoundedRadius: 6,
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

  _SemiGaugePainter({required this.percentage});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final backgroundPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, pi, pi, false, backgroundPaint);

    if (percentage > 0) {
      const gradient = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF137FEC),
          const Color(0xFF3B82F6),
          const Color(0xFF93C5FD),
        ],
        stops: const [0.0, 0.5, 1.0],
      );
      final progressPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round;

      final sweepAngle = pi * percentage.clamp(0.0, 1.0);
      canvas.drawArc(rect, pi, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SemiGaugePainter oldDelegate) {
    return oldDelegate.percentage != percentage;
  }
}
