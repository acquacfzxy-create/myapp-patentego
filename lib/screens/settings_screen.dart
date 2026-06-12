import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_state.dart';
import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../providers/user_state_provider.dart';
import '../services/database_service.dart';
import '../services/firebase_status.dart';
import '../widgets/glass_card.dart';
import 'auth_page.dart';
import 'subscription_page.dart';

/// 設置頁面
/// 提供語言切換、付費狀態查看等功能
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// 構建頭部（參照首頁風格）
  Widget _buildHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        child: Row(
          children: [
            // 返回按鈕
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  size: 20, color: Color(0xFF475569)),
              onPressed: () => Navigator.of(context).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 16),
            // 標題
            Expanded(
              child: Text(
                AppStrings.get('settings_title'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1d1d1f),
                  letterSpacing: -0.5,
                ),
              ),
            ),
            // 占位（保持布局平衡）
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  /// 構建登錄卡片
  Widget _buildLoginCard(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AuthPage(),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.login,
                  color: Colors.amber,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.get('login_to_sync_unlock_vip'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1d1d1f),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppStrings.get('guest_mode_status'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 構建設置項卡片
  /// [isLoading] 為 true 時顯示 [loadingTitle]、[trailing]，並禁用 onTap
  Widget _buildSettingCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Color? textColor,
    bool isLoading = false,
    String? loadingTitle,
    Widget? trailing,
  }) {
    final effectiveTitle =
        isLoading && loadingTitle != null ? loadingTitle : title;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      borderRadius: BorderRadius.circular(20),
      onTap: isLoading ? null : onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  effectiveTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor ?? const Color(0xFF1d1d1f),
                  ),
                ),
                if (subtitle != null && !isLoading) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
          if (onTap != null && !isLoading)
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
            ),
        ],
      ),
    );
  }

  /// 構建開關卡片
  Widget _buildSwitchCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      borderRadius: BorderRadius.circular(20),
      onTap: null,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1d1d1f),
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF0EA5E9),
          ),
        ],
      ),
    );
  }

  /// 切換語言
  Future<void> _changeLanguage(BuildContext context, String newLanguage) async {
    // 使用 Provider 更新語言（會自動通知所有監聽者）
    await context.read<UserStateProvider>().changeLanguage(newLanguage);

    // 關閉對話框
    if (context.mounted) {
      Navigator.pop(context);

      // 顯示成功提示（使用新語言）
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${UserState.languageNames[newLanguage]} ${AppStrings.getWithLanguage(newLanguage, 'confirm').toLowerCase()}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 顯示語言選擇對話框
  void _showLanguageDialog(BuildContext context) {
    final userStateProvider = context.read<UserStateProvider>();
    final currentLanguage = userStateProvider.currentLanguage;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              backgroundColor: Colors.white.withOpacity(0.95),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                AppStrings.get('select_language'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: UserState.supportedLanguages.map((lang) {
                    final isSelected = lang == currentLanguage;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF0EA5E9).withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text(
                          UserState.languageNames[lang] ?? lang,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? const Color(0xFF0EA5E9)
                                : const Color(0xFF1E293B),
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFF0EA5E9))
                            : null,
                        onTap: () {
                          _changeLanguage(context, lang);
                          // Navigator.pop 在 _changeLanguage 中處理
                        },
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final userStateProvider = context.read<UserStateProvider>();
    final uid = FirebaseStatus.currentUserUid;

    final shouldDeleteCloudData = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(AppStrings.get('delete_cloud_data_on_signout_title')),
          content: Text(AppStrings.get('delete_cloud_data_on_signout_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppStrings.get('sign_out_only')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(AppStrings.get('sign_out_and_delete_data')),
            ),
          ],
        );
      },
    );

    if (shouldDeleteCloudData == null) return;
    if (shouldDeleteCloudData && uid != null) {
      await DatabaseService.clearCloudUserData(userId: uid);
    }

    await FirebaseStatus.signOut();
    userStateProvider.clearProgressStats();
  }

  Future<void> _openExternalUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('open_link_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Consumer 監聽 UserStateProvider 的變化
    return Consumer<UserStateProvider>(
      builder: (context, userStateProvider, child) {
        final currentLanguage = userStateProvider.currentLanguage;
        final isVip = userStateProvider.isVip;
        final isLoggedIn = FirebaseStatus.isSignedIn;

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
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // 自定义头部
                SliverToBoxAdapter(
                  child: _buildHeader(context),
                ),
                // 设置项列表
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // 登录提示卡片（未登录时显示）
                      if (!isLoggedIn) ...[
                        _buildLoginCard(context),
                        const SizedBox(height: 12),
                      ],

                      // 語言設置
                      _buildSettingCard(
                        context,
                        icon: Icons.language,
                        iconColor: const Color(0xFF0EA5E9),
                        title: AppStrings.get('language'),
                        subtitle: UserState.languageNames[currentLanguage] ??
                            currentLanguage,
                        onTap: () => _showLanguageDialog(context),
                      ),
                      const SizedBox(height: 12),

                      // 跳过已掌握题目设置
                      _buildSwitchCard(
                        context,
                        icon: Icons.filter_list,
                        iconColor: const Color(0xFF8B5CF6),
                        title: AppStrings.get('skip_mastered_questions'),
                        value: userStateProvider.skipMastered,
                        onChanged: (bool value) {
                          userStateProvider.setSkipMastered(value);
                        },
                      ),
                      const SizedBox(height: 12),

                      // 雲端同步（僅 VIP 用戶）
                      if (isLoggedIn && isVip) ...[
                        const SizedBox(height: 12),
                        _buildSettingCard(
                          context,
                          icon: Icons.cloud_upload,
                          iconColor: const Color(0xFF0EA5E9),
                          title: AppStrings.get('sync_now'),
                          subtitle: AppStrings.get('cloud_sync'),
                          onTap: () =>
                              _handleSyncToCloud(context, userStateProvider),
                          isLoading: userStateProvider.isSyncingToCloud,
                          loadingTitle: AppStrings.get('syncing'),
                          trailing: userStateProvider.isSyncingToCloud
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text(
                            '${AppStrings.get('last_sync_time_prefix')}${userStateProvider.lastSyncTime}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],

                      // 非 VIP 用戶的雲端同步提示
                      if (isLoggedIn && !isVip) ...[
                        const SizedBox(height: 12),
                        _buildSettingCard(
                          context,
                          icon: Icons.cloud_upload,
                          iconColor: Colors.grey,
                          title: AppStrings.get('cloud_sync_title'),
                          subtitle:
                              AppStrings.get('cloud_sync_subtitle_vip_only'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SubscriptionPage(),
                              ),
                            );
                          },
                        ),
                      ],

                      const SizedBox(height: 12),
                      _buildSettingCard(
                        context,
                        icon: Icons.privacy_tip_outlined,
                        iconColor: const Color(0xFF0EA5E9),
                        title: AppStrings.get('privacy_and_terms'),
                        subtitle:
                            '${AppStrings.get('sub_privacy_policy')} / ${AppStrings.get('sub_service_terms')}',
                        onTap: () {
                          showModalBottomSheet<void>(
                            context: context,
                            builder: (sheetContext) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading:
                                        const Icon(Icons.privacy_tip_outlined),
                                    title: Text(
                                        AppStrings.get('sub_privacy_policy')),
                                    onTap: () async {
                                      Navigator.of(sheetContext).pop();
                                      await _openExternalUrl(
                                          context, AppConfig.privacyPolicyUrl);
                                    },
                                  ),
                                  ListTile(
                                    leading:
                                        const Icon(Icons.description_outlined),
                                    title: Text(
                                        AppStrings.get('sub_service_terms')),
                                    onTap: () async {
                                      Navigator.of(sheetContext).pop();
                                      await _openExternalUrl(
                                          context, AppConfig.termsOfServiceUrl);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      _buildSettingCard(
                        context,
                        icon: Icons.support_agent,
                        iconColor: const Color(0xFF22C55E),
                        title: AppStrings.get('support'),
                        subtitle: AppStrings.get('support_subtitle'),
                        onTap: () => _openExternalUrl(
                            context, AppConfig.supportContactUrl),
                      ),
                      const SizedBox(height: 12),

                      // 關於
                      _buildSettingCard(
                        context,
                        icon: Icons.info,
                        iconColor: const Color(0xFF6B7280),
                        title: AppStrings.get('about'),
                        subtitle:
                            '${AppStrings.get('version')} ${AppConfig.appVersion}',
                        onTap: null,
                      ),

                      const SizedBox(height: 12),

                      // 重置所有学习进度
                      _buildSettingCard(
                        context,
                        icon: Icons.delete_forever,
                        iconColor: Colors.red,
                        title: AppStrings.getWithLanguage(
                            currentLanguage, 'reset_progress'),
                        subtitle: null,
                        onTap: () => _showResetProgressDialog(
                            context, userStateProvider),
                        textColor: Colors.red,
                      ),

                      // 登出
                      if (isLoggedIn) ...[
                        const SizedBox(height: 12),
                        _buildSettingCard(
                          context,
                          icon: Icons.logout,
                          iconColor: Colors.red,
                          title: AppStrings.get('sign_out'),
                          subtitle: null,
                          onTap: () => _handleSignOut(context),
                          textColor: Colors.red,
                        ),
                      ],

                      const SizedBox(height: 24),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 显示重置学习进度的确认对话框
  Future<void> _showResetProgressDialog(
    BuildContext context,
    UserStateProvider userStateProvider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        // 使用 Consumer 监听语言变化，确保对话框文字能实时更新
        return Consumer<UserStateProvider>(
          builder: (context, provider, child) {
            final currentLang = provider.currentLanguage;
            return AlertDialog(
              title: Text(AppStrings.getWithLanguage(
                  currentLang, 'reset_confirm_title')),
              content: Text(AppStrings.getWithLanguage(
                  currentLang, 'reset_confirm_content')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child:
                      Text(AppStrings.getWithLanguage(currentLang, 'cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  child:
                      Text(AppStrings.getWithLanguage(currentLang, 'confirm')),
                ),
              ],
            );
          },
        );
      },
    );

    // 如果用户确认重置
    if (confirmed == true && context.mounted) {
      // 显示加载指示器
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext loadingContext) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      );

      try {
        // 调用重置方法
        final success = await userStateProvider.handleResetProgress();

        // 关闭加载指示器
        if (context.mounted) {
          Navigator.of(context).pop();
        }

        if (success) {
          // 显示成功提示（使用当前语言）
          if (context.mounted) {
            final currentLang = userStateProvider.currentLanguage;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppStrings.getWithLanguage(
                    currentLang, 'reset_progress_success')),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }

          // 关闭对话框并返回上一页
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        } else {
          // 显示失败提示（使用当前语言）
          if (context.mounted) {
            final currentLang = userStateProvider.currentLanguage;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppStrings.getWithLanguage(
                    currentLang, 'reset_progress_failed')),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        // 关闭加载指示器
        if (context.mounted) {
          Navigator.of(context).pop();
        }

        // 显示错误提示（使用当前语言）
        if (context.mounted) {
          final currentLang = userStateProvider.currentLanguage;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${AppStrings.getWithLanguage(currentLang, 'reset_progress_failed')}: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  /// 處理雲端同步（按鈕內顯示「同步中...」+ 小轉圈，不再彈全屏 Loading）
  Future<void> _handleSyncToCloud(
    BuildContext context,
    UserStateProvider userStateProvider,
  ) async {
    if (!userStateProvider.isVip) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SubscriptionPage(),
        ),
      );
      return;
    }

    if (!FirebaseStatus.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.get('sync_login_required')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final result = await userStateProvider.syncProgressToCloud();
      if (!context.mounted) return;
      if (result.isTimeout) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.get('sync_timeout_retry')),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success
              ? AppStrings.get('sync_success')
              : AppStrings.get('sync_partial_error')),
          backgroundColor: result.success ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppStrings.get('sync_failed_prefix')}$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
