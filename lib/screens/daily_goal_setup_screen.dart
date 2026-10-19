import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../models/daily_goal_plan.dart';
import '../providers/user_state_provider.dart';
import '../services/access_policy.dart';
import '../widgets/glass_card.dart';
import 'home_screen.dart';
import 'subscription_page.dart';

class DailyGoalSetupScreen extends StatefulWidget {
  const DailyGoalSetupScreen({
    super.key,
    this.isEditing = false,
  });

  final bool isEditing;

  @override
  State<DailyGoalSetupScreen> createState() => _DailyGoalSetupScreenState();
}

class _DailyGoalSetupScreenState extends State<DailyGoalSetupScreen> {
  final TextEditingController _goalController = TextEditingController();
  double _selectedGoal = AccessPolicy.freeDailyQuizLimit.toDouble();
  int? _selectedDurationDays;
  DateTime? _selectedTargetDate;
  bool _didInitialize = false;

  String get _currentLanguage =>
      context.read<UserStateProvider>().currentLanguage;

  String _t(String key) => AppStrings.getWithLanguage(_currentLanguage, key);

  bool get _isRtl => _currentLanguage == 'ur';

  int get _goal => DailyGoalPlan.normalizeGoal(_selectedGoal.round());

  int get _remainingQuestions => DailyGoalPlan.remainingQuestions(
        context.read<UserStateProvider>().attemptedCount,
      );

  DailyPlanAllocation get _allocation {
    final provider = context.read<UserStateProvider>();
    final targetDate = _selectedTargetDate;
    if (targetDate != null) {
      return DailyGoalPlan.recalculateForTarget(
        remainingQuestions: _remainingQuestions,
        attemptedQuestions: provider.attemptedCount,
        targetDate: targetDate,
        fallbackTotalGoal: _goal,
      );
    }
    return DailyGoalPlan.allocateTotalGoal(
      totalGoal: _goal,
      remainingQuestions: _remainingQuestions,
      attemptedQuestions: provider.attemptedCount,
    );
  }

  int get _estimatedDays => _allocation.daysRemaining;

  bool get _exceedsFreeQuota =>
      !context.read<UserStateProvider>().isVip &&
      _goal > AccessPolicy.freeDailyQuizLimit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialize) return;
    _didInitialize = true;
    final savedGoal = context.read<UserStateProvider>().dailyStudyGoal;
    _selectedGoal = savedGoal.toDouble();
    _selectedTargetDate = context.read<UserStateProvider>().studyPlanTargetDate;
    _goalController.text = savedGoal.toString();
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  void _setGoal(
    int goal, {
    int? durationDays,
    DateTime? targetDate,
  }) {
    final normalized = DailyGoalPlan.normalizeGoal(goal);
    setState(() {
      _selectedGoal = normalized.toDouble();
      _selectedDurationDays = durationDays;
      _selectedTargetDate = targetDate ??
          DailyGoalPlan.targetDateForTotalGoal(
            remainingQuestions: _remainingQuestions,
            attemptedQuestions:
                context.read<UserStateProvider>().attemptedCount,
            totalGoal: normalized,
          );
      _goalController.text = normalized.toString();
      _goalController.selection = TextSelection.collapsed(
        offset: _goalController.text.length,
      );
    });
  }

  void _selectDuration(int days) {
    final today = DailyGoalPlan.dateOnly(DateTime.now());
    final targetDate = today.add(Duration(days: days - 1));
    final allocation = DailyGoalPlan.recalculateForTarget(
      remainingQuestions: _remainingQuestions,
      attemptedQuestions: context.read<UserStateProvider>().attemptedCount,
      targetDate: targetDate,
      fallbackTotalGoal: _goal,
    );
    _setGoal(
      allocation.totalGoal,
      durationDays: days,
      targetDate: targetDate,
    );
  }

  void _onCustomGoalChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    setState(() {
      _selectedGoal = DailyGoalPlan.normalizeGoal(parsed).toDouble();
      _selectedDurationDays = null;
      _selectedTargetDate = DailyGoalPlan.targetDateForTotalGoal(
        remainingQuestions: _remainingQuestions,
        attemptedQuestions: context.read<UserStateProvider>().attemptedCount,
        totalGoal: parsed,
      );
    });
  }

  Future<void> _saveGoal() async {
    if (_exceedsFreeQuota) {
      await _openVipUnlock();
      if (!mounted || _exceedsFreeQuota) return;
    }

    final targetDate = _selectedTargetDate;
    _setGoal(_goal, targetDate: targetDate);
    await context.read<UserStateProvider>().setDailyStudyGoal(
          _goal,
          targetDate: targetDate,
        );

    if (!mounted) return;
    if (widget.isEditing) {
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _openVipUnlock() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SubscriptionPage(),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isVip = context.watch<UserStateProvider>().isVip;
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    final exceedsFreeQuota = !isVip && _goal > AccessPolicy.freeDailyQuizLimit;
    final goalAccent = exceedsFreeQuota
        ? AppTheme.warningTextFor(context)
        : AppTheme.primaryFor(context);
    final sliderValue = _selectedGoal.clamp(
      DailyGoalPlan.minDailyGoal.toDouble(),
      DailyGoalPlan.sliderMaxGoal.toDouble(),
    );
    const freeMarkerPosition =
        (AccessPolicy.freeDailyQuizLimit - DailyGoalPlan.minDailyGoal) /
            (DailyGoalPlan.sliderMaxGoal - DailyGoalPlan.minDailyGoal);

    return Directionality(
      textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: AppTheme.pageDecorationFor(context),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 40,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.isEditing) ...[
                          Row(
                            children: [
                              IconButton(
                                tooltip: MaterialLocalizations.of(context)
                                    .backButtonTooltip,
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.arrow_back_ios_new),
                              ),
                              Expanded(
                                child: Text(
                                  _t('daily_goal_manage_title'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                          const SizedBox(height: 14),
                        ],
                        GlassCard(
                          borderRadius: BorderRadius.circular(32),
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: AppTheme.primarySoftFor(context),
                                  shape: isRetro
                                      ? BoxShape.rectangle
                                      : BoxShape.circle,
                                  border: isRetro
                                      ? Border.all(color: AppTheme.retroLine)
                                      : null,
                                ),
                                child: Icon(
                                  Icons.flag_rounded,
                                  color: goalAccent,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.isEditing
                                    ? _t('daily_goal_manage_title')
                                    : _t('daily_goal_setup_title'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _t('daily_goal_setup_subtitle'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                _t('daily_goal_finish_in'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: DailyGoalPlan.suggestedDurations
                                    .map(
                                      (days) => ChoiceChip(
                                        selected: _selectedDurationDays == days,
                                        selectedColor: exceedsFreeQuota
                                            ? AppTheme.warningFor(context)
                                                .withOpacity(0.16)
                                            : null,
                                        label: Text(
                                          _t('daily_goal_duration_option')
                                              .replaceAll(
                                            '{days}',
                                            days.toString(),
                                          ),
                                        ),
                                        onSelected: (_) =>
                                            _selectDuration(days),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                _t('daily_goal_custom_label'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 132,
                                    child: TextField(
                                      key: const ValueKey('daily_goal_input'),
                                      controller: _goalController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(4),
                                      ],
                                      onChanged: _onCustomGoalChanged,
                                      onSubmitted: (_) => _setGoal(_goal),
                                      style: TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                        color: goalAccent,
                                      ),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: goalAccent.withOpacity(0.06),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: isRetro
                                              ? BorderRadius.zero
                                              : BorderRadius.circular(16),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      _t('daily_goal_questions_per_day'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LayoutBuilder(
                                builder: (context, sliderConstraints) {
                                  final markerStart =
                                      (sliderConstraints.maxWidth - 72) *
                                          freeMarkerPosition;
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 8,
                                          activeTrackColor: goalAccent,
                                          inactiveTrackColor:
                                              goalAccent.withOpacity(0.16),
                                          thumbColor: goalAccent,
                                          overlayColor:
                                              goalAccent.withOpacity(0.12),
                                        ),
                                        child: Slider(
                                          min: DailyGoalPlan.minDailyGoal
                                              .toDouble(),
                                          max: DailyGoalPlan.sliderMaxGoal
                                              .toDouble(),
                                          divisions: 58,
                                          value: sliderValue,
                                          onChanged: (value) {
                                            _setGoal(
                                              (value / 5).round() * 5,
                                            );
                                          },
                                        ),
                                      ),
                                      PositionedDirectional(
                                        top: 42,
                                        start: markerStart,
                                        child: _FreeQuotaBadge(
                                          label: _t('daily_goal_free_quota'),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 42),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: exceedsFreeQuota
                                      ? AppTheme.warningFor(context)
                                          .withOpacity(0.12)
                                      : AppTheme.primarySoftFor(context),
                                  borderRadius: isRetro
                                      ? BorderRadius.zero
                                      : BorderRadius.circular(16),
                                  border: isRetro
                                      ? Border.all(color: AppTheme.retroLine)
                                      : null,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      _t('daily_goal_remaining_questions')
                                          .replaceAll(
                                        '{count}',
                                        _remainingQuestions.toString(),
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _estimatedDays == 0
                                          ? _t('daily_goal_all_done')
                                          : _t('daily_goal_estimated_days')
                                              .replaceAll(
                                              '{days}',
                                              _estimatedDays.toString(),
                                            ),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _PlanMetric(
                                            icon: Icons.auto_awesome_rounded,
                                            label: _t(
                                              'daily_goal_new_questions',
                                            ),
                                            count: _allocation.newGoal,
                                            color: goalAccent,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _PlanMetric(
                                            icon: Icons.replay_rounded,
                                            label: _t(
                                              'daily_goal_review_questions',
                                            ),
                                            count: _allocation.reviewGoal,
                                            color: isRetro
                                                ? AppTheme.retroPrimary
                                                : colorScheme.secondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _t('daily_goal_dynamic_hint'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.35,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (exceedsFreeQuota) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.warningFor(context)
                                        .withOpacity(0.12),
                                    borderRadius: isRetro
                                        ? BorderRadius.zero
                                        : BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppTheme.warningTextFor(context)
                                          .withOpacity(0.28),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        color: AppTheme.warningTextFor(context),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _t('daily_goal_quota_warning')
                                                  .replaceAll(
                                                    '{goal}',
                                                    _goal.toString(),
                                                  )
                                                  .replaceAll(
                                                    '{quota}',
                                                    AccessPolicy
                                                        .freeDailyQuizLimit
                                                        .toString(),
                                                  ),
                                              style: TextStyle(
                                                color: AppTheme.warningTextFor(
                                                  context,
                                                ),
                                                fontSize: 12,
                                                height: 1.4,
                                              ),
                                            ),
                                            TextButton(
                                              key: const Key(
                                                'daily_goal_vip_unlock',
                                              ),
                                              onPressed: _openVipUnlock,
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    AppTheme.warningTextFor(
                                                        context),
                                                padding: const EdgeInsets.only(
                                                  top: 5,
                                                ),
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              child: Text(
                                                _t('unlock_now'),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _saveGoal,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: goalAccent,
                                    foregroundColor: colorScheme.onPrimary,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: isRetro
                                          ? BorderRadius.zero
                                          : BorderRadius.circular(28),
                                    ),
                                  ),
                                  child: Text(
                                    exceedsFreeQuota
                                        ? _t('unlock_now')
                                        : widget.isEditing
                                            ? _t('daily_goal_save_changes')
                                            : _t('daily_goal_start_plan'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
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
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanMetric extends StatelessWidget {
  const _PlanMetric({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isRetro = AppTheme.isRetroFor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: isRetro ? BorderRadius.zero : BorderRadius.circular(12),
        border: isRetro ? Border.all(color: AppTheme.retroLine) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$label $count',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FreeQuotaBadge extends StatelessWidget {
  const _FreeQuotaBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);
    return Transform.translate(
      offset: const Offset(-10, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.primary.withOpacity(0.12),
          borderRadius:
              isRetro ? BorderRadius.zero : BorderRadius.circular(999),
          border: Border.all(color: colorScheme.primary.withOpacity(0.25)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
