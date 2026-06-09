import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_state_provider.dart';
import '../widgets/glass_card.dart';
import '../config/app_strings.dart';

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
        // 顯示具體錯誤原因
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
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
          content: Text(AppStrings.getWithLanguage(lang, 'merge_progress_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppStrings.getWithLanguage(lang, 'merge_progress_later')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(AppStrings.getWithLanguage(lang, 'merge_progress_confirm')),
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
              content: Text(AppStrings.getWithLanguage(lang, 'merge_progress_success')),
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
                  '${AppStrings.getWithLanguage(lang, 'merge_progress_failed')} (${e.toString()})'),
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
    final lang = context.watch<UserStateProvider>().currentLanguage;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE0F7FA), // 左上角：极浅蓝色
              Color(0xFFF0F9FF), // 中间：极浅蓝色
              Color(0xFFFFFFFF), // 右下角：白色
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
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
                            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF475569)),
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
                            const Icon(
                              Icons.lock_outline,
                              size: 72,
                              color: Color(0xFF0EA5E9),
                            ),
                            const SizedBox(height: 24),
                            // 標題
                            Text(
                              AppStrings.getWithLanguage(lang, 'auth_welcome'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1d1d1f),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // 描述
                            Text(
                              AppStrings.getWithLanguage(lang, 'auth_benefits'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
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
                                        action: () => context.read<UserStateProvider>().signInWithGoogle(),
                                      ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 16),
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
                                    Text(
                                      AppStrings.getWithLanguage(lang, 'auth_google'),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1d1d1f),
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
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
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
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: isLoading
                                      ? null
                                      : () => _handleSignIn(
                                            providerKey: 'apple',
                                            action: () => context.read<UserStateProvider>().signInWithApple(),
                                          ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.apple,
                                          size: 24,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          AppStrings.getWithLanguage(lang, 'auth_apple'),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
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
                              onPressed: isLoading
                                  ? null
                                  : _handleClose,
                              child: Text(
                                AppStrings.getWithLanguage(lang, 'auth_guest_later'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
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
