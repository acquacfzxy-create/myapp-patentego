import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_strings.dart';
import '../models/user_state.dart';
import '../providers/user_state_provider.dart';
import '../widgets/glass_card.dart';
import 'home_screen.dart';

/// 語言選擇頁面
/// 首次啟動時顯示，讓用戶選擇首選語言
class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen>
    with SingleTickerProviderStateMixin {
  String _selectedLanguage = UserState.supportedLanguages.first;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isRtlLanguage(String lang) => lang == 'ur';

  String _localized(String lang, String key) =>
      AppStrings.getWithLanguage(lang, key);

  /// 不同語言根據字形調整字號，保證視覺平衡
  double _getLanguageFontSize(String lang) {
    switch (lang) {
      case 'uk':
      case 'ur':
      case 'pa':
        return 22; // 特殊字形語言放大約 20%
      default:
        return 18;
    }
  }

  /// 不同語言的行高微調，讓基線更貼齊
  double _getLanguageLineHeight(String lang) {
    switch (lang) {
      case 'uk':
      case 'ur':
      case 'pa':
        return 1.1;
      default:
        return 1.0;
    }
  }

  /// 每種語言的「原生首字符」
  String _getLanguageInitial(String lang) {
    switch (lang) {
      case 'zh':
        return '中';
      case 'en':
        return 'E';
      case 'ru':
        return 'Р';
      case 'uk':
        return 'У';
      case 'pa':
        return 'ਪ';
      case 'ur':
        return 'ا';
      default:
        final name = UserState.languageNames[lang] ?? lang;
        return name.isNotEmpty ? name[0] : '?';
    }
  }

  Future<void> _confirmAndEnterHome(BuildContext context) async {
    final lang = _selectedLanguage;
    final userStateProvider = context.read<UserStateProvider>();
    await userStateProvider.changeLanguage(lang);

    if (!context.mounted) return;

    // 使用淡入淡出動畫進入主頁
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  /// 構建單個語言選項（含入場動畫）
  Widget _buildLanguageTile(String lang, List<String> allLanguages) {
    final isSelected = lang == _selectedLanguage;
    final languageName = UserState.languageNames[lang] ?? lang;
    final fontSize = _getLanguageFontSize(lang);
    final lineHeight = _getLanguageLineHeight(lang);
    final initial = _getLanguageInitial(lang);

    final int itemIndex = allLanguages.indexOf(lang);
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        0.05 * itemIndex,
        0.4 + 0.05 * itemIndex,
        curve: Curves.easeOut,
      ),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(animation),
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedLanguage = lang;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: isSelected
                  ? const Color(0xFFE3F2FF)
                  : Colors.grey[50]!.withOpacity(0.95),
              border: Border.all(
                color: isSelected ? const Color(0xFF137FEC) : Colors.grey[200]!,
                width: isSelected ? 1.6 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 左側語言首字符（圓形背景）
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                        isSelected ? const Color(0xFF137FEC) : Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.grey[700],
                    ),
                    child: Text(initial),
                  ),
                ),
                const SizedBox(width: 12),
                // 語言名稱
                Expanded(
                  child: Directionality(
                    textDirection: _isRtlLanguage(lang)
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: Text(
                      languageName,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        height: lineHeight,
                        color: const Color(0xFF0F172A),
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

  @override
  Widget build(BuildContext context) {
    const languages = UserState.supportedLanguages;
    final selectedLanguageIsRtl = _isRtlLanguage(_selectedLanguage);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE0F7FA),
              Color(0xFFF0F9FF),
              Color(0xFFFFFFFF),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                const SizedBox(height: 8),
                // 中央大玻璃卡片
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: GlassCard(
                        borderRadius: BorderRadius.circular(32),
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 頂部裝飾：地球圖標 + 動態標題
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          Color(0x330EA5E9),
                                          Colors.transparent,
                                        ],
                                        radius: 0.9,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.public,
                                      size: 36,
                                      color: Color(0xFF0EA5E9),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Directionality(
                                    textDirection: selectedLanguageIsRtl
                                        ? TextDirection.rtl
                                        : TextDirection.ltr,
                                    child: Text(
                                      _localized(
                                          _selectedLanguage, 'select_language'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // 語言列表（卡片式，帶入場動畫）
                            ...languages.map((lang) {
                              return _buildLanguageTile(lang, languages);
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 底部「開始學習」按鈕（膠囊樣式，對標 CONSEGNA）
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _confirmAndEnterHome(context),
                      borderRadius: BorderRadius.circular(32),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withOpacity(0.25),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (selectedLanguageIsRtl) ...[
                              Text(
                                _localized(_selectedLanguage, 'start_learning'),
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            if (!selectedLanguageIsRtl)
                              const SizedBox(width: 8),
                            if (!selectedLanguageIsRtl)
                              Text(
                                _localized(_selectedLanguage, 'start_learning'),
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                          ],
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
}
