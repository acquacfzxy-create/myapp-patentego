import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_state_provider.dart';
import '../widgets/glass_card.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../config/user_error_copy.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  String? _loadingProvider;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _handleSignIn({
    required String providerKey,
    required Future<void> Function() action,
  }) async {
    if (_loadingProvider != null || !mounted) return;

    // 設置加載狀態
    setState(() {
      _loadingProvider = providerKey;
    });

    try {
      await action();
      if (mounted) {
        // 登入成功後，先處理遊客進度合併
        await _maybeMergeGuestProgress();
        if (mounted) {
          // 登入成功，返回上一頁（首頁）
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        // 只顯示本地化文案；未知的 SDK 錯誤統一顯示通用提示。
        final errorMessage = UserErrorCopy.auth(
          e,
          language: context.read<UserStateProvider>().currentLanguage,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingProvider = null;
        });
      }
    }
  }

  Future<void> _maybeMergeGuestProgress() async {
    final userStateProvider = context.read<UserStateProvider>();
    final hasGuestData = await userStateProvider.hasGuestProgress();
    if (!hasGuestData || !mounted) return;

    final lang = userStateProvider.currentLanguage;
    final shouldMerge = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(AppStrings.getWithLanguage(lang, 'merge_progress_title')),
          content:
              Text(AppStrings.getWithLanguage(lang, 'merge_progress_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                  AppStrings.getWithLanguage(lang, 'merge_progress_later')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                  AppStrings.getWithLanguage(lang, 'merge_progress_confirm')),
            ),
          ],
        );
      },
    );

    if (shouldMerge == true && mounted) {
      try {
        await userStateProvider.mergeGuestProgressToCurrentUser();
        if (mounted) {
          final lang = context.read<UserStateProvider>().currentLanguage;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppStrings.getWithLanguage(lang, 'merge_progress_success')),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          final lang = context.read<UserStateProvider>().currentLanguage;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppStrings.getWithLanguage(lang, 'merge_progress_failed')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _handleClose() {
    if (_loadingProvider != null) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _loadingProvider != null;
    final userStateProvider = context.watch<UserStateProvider>();
    final lang = userStateProvider.currentLanguage;
    final colorScheme = Theme.of(context).colorScheme;
    final isRetro = AppTheme.isRetroFor(context);

    return Scaffold(
      // 頁面底色由主題提供，內容較短時也不會露出黑色窗口底。
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: AppTheme.pageDecorationFor(context),
        child: Stack(
          children: [
            // 主要內容（底層）
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // 返回按鈕（固定在頂部）
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                            icon:
                                const Icon(Icons.arrow_back_ios_new, size: 20),
                            color: colorScheme.onSurfaceVariant,
                            onPressed: isLoading ? null : _handleClose,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    // 使用 Expanded 和 Spacer 均勻分布內容
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 20),
                            // 圖標
                            Icon(
                              Icons.lock_outline,
                              size: 72,
                              color: AppTheme.primaryFor(context),
                            ),
                            const SizedBox(height: 24),
                            // 標題
                            Text(
                              AppStrings.getWithLanguage(lang, 'auth_welcome'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // 描述
                            Text(
                              AppStrings.getWithLanguage(lang, 'auth_benefits'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 48),
                            // Google 登錄按鈕
                            GlassCard(
                              padding: EdgeInsets.zero,
                              borderRadius: BorderRadius.circular(16),
                              onTap: isLoading
                                  ? null
                                  : () => _handleSignIn(
                                        providerKey: 'google',
                                        action: () => context
                                            .read<UserStateProvider>()
                                            .signInWithGoogle(),
                                      ),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.g_mobiledata,
                                        size: 24,
                                        color: Color(0xFF4285F4),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // 长语言（ru/uk/pa）或放大字号时允许换行，避免溢出。
                                    Flexible(
                                      child: Text(
                                        AppStrings.getWithLanguage(
                                            lang, 'auth_google'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Apple 登錄按鈕
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: isRetro
                                    ? BorderRadius.zero
                                    : BorderRadius.circular(16),
                                boxShadow: isRetro
                                    ? const []
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: isRetro
                                      ? BorderRadius.zero
                                      : BorderRadius.circular(16),
                                  onTap: isLoading
                                      ? null
                                      : () => _handleSignIn(
                                            providerKey: 'apple',
                                            action: () => context
                                                .read<UserStateProvider>()
                                                .signInWithApple(),
                                          ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.apple,
                                          size: 24,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 12),
                                        Flexible(
                                          child: Text(
                                            AppStrings.getWithLanguage(
                                                lang, 'auth_apple'),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            // 游客模式按鈕
                            TextButton(
                              onPressed: isLoading ? null : _handleClose,
                              child: Text(
                                AppStrings.getWithLanguage(
                                    lang, 'auth_guest_later'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 加載遮罩（頂層）
            if (isLoading)
              Positioned.fill(
                child: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Container(
                      color: Colors.black.withOpacity(0.2),
                      child: const Center(
                        child: CircularProgressIndicator(),
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
