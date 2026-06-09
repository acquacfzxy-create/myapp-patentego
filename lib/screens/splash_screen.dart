import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_strings.dart';
import '../models/user_state.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// 首次啟動無語言記錄時，啟動頁 Slogan 預設為英文。
  static const String _kPrefsLanguageKey = 'current_language';
  static const String _defaultSplashLanguage = 'en';

  late final AnimationController _logoController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  late final AnimationController _taglineController;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _taglineOpacity;

  String _sloganLanguageCode = _defaultSplashLanguage;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    final logoCurved = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOutCubic,
    );

    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(logoCurved);
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(logoCurved);

    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    final taglineCurved = CurvedAnimation(
      parent: _taglineController,
      curve: Curves.easeOutCubic,
    );

    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(taglineCurved);

    _taglineOpacity =
        Tween<double>(begin: 0.0, end: 1.0).animate(taglineCurved);

    _logoController.forward();

    _preloadSloganLanguage();

    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _taglineController.forward();
    });
  }

  /// 異步讀取語言，不阻塞 Logo 動畫與上層最短展示時間（SplashBootstrap）。
  void _preloadSloganLanguage() {
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      final saved = prefs.getString(_kPrefsLanguageKey);
      const supported = UserState.supportedLanguages;
      final code =
          (saved != null && saved.isNotEmpty && supported.contains(saved))
              ? saved
              : _defaultSplashLanguage;
      setState(() => _sloganLanguageCode = code);
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slogan =
        AppStrings.getWithLanguage(_sloganLanguageCode, 'splash_slogan');

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _logoController,
                      builder: (context, child) {
                        return FadeTransition(
                          opacity: _logoOpacity,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: child,
                          ),
                        );
                      },
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        width: 150,
                        height: 150,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 60),
              child: SlideTransition(
                position: _taglineSlide,
                child: FadeTransition(
                  opacity: _taglineOpacity,
                  child: Text(
                    slogan,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      letterSpacing: 0.2,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
