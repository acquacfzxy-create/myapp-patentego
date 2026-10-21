import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../providers/user_state_provider.dart';
import '../widgets/bouncy_press.dart';
import 'daily_goal_setup_screen.dart';

/// 首次啟動：選完語言後選主題。點選即時套用，整頁立刻換成該主題，
/// 讓使用者直接看到效果；之後仍可在設定裡更換。
class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

  static const _modes = [
    AppThemeMode.classic,
    AppThemeMode.night,
    AppThemeMode.retro,
  ];

  static String nameKey(AppThemeMode mode) => switch (mode) {
        AppThemeMode.classic => 'theme_classic',
        AppThemeMode.night => 'theme_dark',
        AppThemeMode.retro => 'theme_retro',
      };

  static String descKey(AppThemeMode mode) => switch (mode) {
        AppThemeMode.classic => 'theme_classic_desc',
        AppThemeMode.night => 'theme_dark_desc',
        AppThemeMode.retro => 'theme_retro_desc',
      };

  void _next(BuildContext context) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const DailyGoalSetupScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserStateProvider>();
    final lang = user.currentLanguage;
    String t(String key) => AppStrings.getWithLanguage(lang, key);
    final ink = AppTheme.inkFor(context);
    final muted = AppTheme.mutedFor(context);
    final isRetro = AppTheme.isRetroFor(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: AppTheme.pageDecorationFor(context),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 標題、說明與三個選項一起捲動，大字號時也不會擠爆版面。
                Expanded(
                  child: ListView(
                    children: [
                      Text(
                        t('theme_pick_title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t('theme_pick_subtitle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: muted),
                      ),
                      const SizedBox(height: 20),
                      for (final mode in _modes) ...[
                        _ThemeOption(
                          key: Key('theme_option_${mode.name}'),
                          mode: mode,
                          title: t(nameKey(mode)),
                          description: t(descKey(mode)),
                          selected: user.themeMode == mode,
                          onTap: () => user.setThemeMode(mode),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                BouncyPress(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(isRetro ? 0 : 14),
                      boxShadow: AppTheme.chunkyShadowFor(context),
                    ),
                    child: FilledButton(
                      key: const Key('theme_pick_next'),
                      onPressed: () => _next(context),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        backgroundColor: AppTheme.accentFor(context),
                        foregroundColor: AppTheme.onAccentFor(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(isRetro ? 0 : 14),
                          side: BorderSide(
                            color:
                                isRetro ? AppTheme.retroLine : AppTheme.roadInk,
                            width: 2,
                          ),
                        ),
                        textStyle: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(
                                fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      child: Text(t('theme_pick_next')),
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
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    super.key,
    required this.mode,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final AppThemeMode mode;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRetro = AppTheme.isRetroFor(context);
    final radius = BorderRadius.circular(isRetro ? 0 : 20);
    final accent =
        isRetro ? AppTheme.retroPrimary : AppTheme.primaryFor(context);
    return Semantics(
      button: true,
      selected: selected,
      child: BouncyPress(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceFor(context),
              borderRadius: radius,
              border: Border.all(
                color: selected ? accent : AppTheme.lineFor(context),
                width: selected ? 3 : 1.5,
              ),
              boxShadow: AppTheme.cardShadowFor(context),
            ),
            child: Row(
              children: [
                _ThemePreview(mode: mode),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.inkFor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppTheme.mutedFor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? accent : AppTheme.lineFor(context),
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 主題縮圖：用該主題自己的顏色畫一個迷你答題畫面（題目卡 + 連對徽章 + 兩個按鈕），
/// 與目前套用的主題無關，三張縮圖始終各自呈現本來的樣子。
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.mode});

  final AppThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final retro = mode == AppThemeMode.retro;
    final night = mode == AppThemeMode.night;
    final page = retro
        ? AppTheme.retroPage
        : night
            ? AppTheme.roadNightPage
            : AppTheme.roadPage;
    final card = retro
        ? AppTheme.retroSurface
        : night
            ? AppTheme.roadNightSurface
            : Colors.white;
    final line = retro
        ? AppTheme.retroLine
        : night
            ? AppTheme.roadNightLine
            : AppTheme.roadLine;
    final text = retro
        ? AppTheme.retroInk
        : night
            ? AppTheme.roadNightInk
            : AppTheme.roadInk;
    final primary = retro
        ? AppTheme.retroPrimary
        : night
            ? AppTheme.roadNightPrimary
            : AppTheme.roadPrimary;
    final r = retro ? 0.0 : 6.0;

    Widget bar(double w, Color c) => Container(
          width: w,
          height: 4,
          margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(retro ? 0 : 2),
          ),
        );

    return Container(
      width: 72,
      height: 96,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: page,
        borderRadius: BorderRadius.circular(retro ? 0 : 12),
        border: Border.all(color: line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(r),
                border: Border.all(color: line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(40, text),
                  bar(32, text),
                  bar(24, text.withOpacity(0.5)),
                  const Spacer(),
                  Container(
                    height: 9,
                    decoration: BoxDecoration(
                      color: retro ? AppTheme.retroPrimary : primary,
                      borderRadius: BorderRadius.circular(r),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(r),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(r),
                    border: Border.all(color: line),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
