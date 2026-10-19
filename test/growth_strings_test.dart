import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/models/user_state.dart';

void main() {
  const growthKeys = [
    'growth_session_summary_title',
    'growth_session_answered',
    'growth_session_correct',
    'growth_newly_mastered',
    'growth_mistakes_resolved',
    'growth_continue_practice',
    'growth_finish_session',
    'growth_today_recommendation',
    'growth_recommend_mistakes',
    'growth_recommend_weak_chapter',
    'growth_recommend_random',
    'growth_start',
    'growth_week_title',
    'growth_no_activity',
    'growth_study_days',
    'growth_answered',
    'chapter_capability_title',
    'chapter_capability_show_all',
    'chapter_capability_show_priority',
    'chapter_capability_not_started',
    'chapter_capability_learning',
    'chapter_capability_needs_attention',
    'chapter_capability_stable',
    'chapter_capability_stats',
    'chapter_capability_start',
    'chapter_capability_strengthen',
    'chapter_capability_review',
    'chapter_strengthening_completed',
    'chapter_strengthening_mastered_change',
    'chapter_strengthening_mistakes_change',
    'chapter_strengthening_state_change',
    'chapter_strengthening_back_to_map',
    'daily_goal_manage_title',
    'daily_goal_settings_subtitle',
    'daily_goal_finish_in',
    'daily_goal_duration_option',
    'daily_goal_custom_label',
    'daily_goal_remaining_questions',
    'daily_goal_quota_warning',
    'daily_goal_save_changes',
    'daily_goal_new_questions',
    'daily_goal_review_questions',
    'spaced_review_status',
    'daily_goal_dynamic_hint',
    'daily_goal_dynamic_short',
    'daily_goal_start_today_plan',
    'daily_goal_plan_complete',
    'daily_goal_no_plan_questions',
    'learning_streak_days',
    'learning_streak_active_today',
    'learning_streak_remaining',
  ];

  test('every supported language has growth and capability copy', () {
    for (final language in UserState.supportedLanguages) {
      for (final key in growthKeys) {
        expect(AppStrings.getWithLanguage(language, key), isNot(key));
      }
    }
  });
}
