import 'package:flutter/material.dart';

import '../providers/user_state_provider.dart';
import 'home_screen.dart';
import 'language_selection_screen.dart';
import 'splash_screen.dart';

/// 啟動引導：先展示 Splash（含動畫），初始化完成後以 PageRouteBuilder 平滑切換到首頁/語言頁。
class SplashBootstrap extends StatefulWidget {
  const SplashBootstrap({super.key});

  @override
  State<SplashBootstrap> createState() => _SplashBootstrapState();
}

class _SplashBootstrapState extends State<SplashBootstrap> {
  bool _didRoute = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted || _didRoute) return;

    final startedAt = DateTime.now();
    final hasSelectedLanguage = await UserStateProvider.hasSelectedLanguage();

    // 讓 Splash 動畫至少完整播放一次（避免「剛閃一下就切走」）
    const minSplash = Duration(milliseconds: 1200);
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < minSplash) {
      await Future<void>.delayed(minSplash - elapsed);
    }

    if (!mounted || _didRoute) return;
    _didRoute = true;

    final next = hasSelectedLanguage == true
        ? const HomeScreen()
        : const LanguageSelectionScreen();

    await Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, animation, secondaryAnimation) => next,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.06, 0.02),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
