import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_state.dart';
import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../providers/user_state_provider.dart';
import 'premium_screen.dart';

/// 設置頁面
/// 提供語言切換、付費狀態查看等功能
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
          content: Text('${UserState.languageNames[newLanguage]} ${AppStrings.getWithLanguage(newLanguage, 'confirm').toLowerCase()}'),
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
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(AppStrings.get('select_language')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: UserState.supportedLanguages.map((lang) {
                final isSelected = lang == currentLanguage;
                return ListTile(
                  title: Text(UserState.languageNames[lang] ?? lang),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Colors.blue)
                      : null,
                  onTap: () {
                    _changeLanguage(context, lang);
                    // Navigator.pop 在 _changeLanguage 中處理
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Consumer 監聽 UserStateProvider 的變化
    return Consumer<UserStateProvider>(
      builder: (context, userStateProvider, child) {
        final currentLanguage = userStateProvider.currentLanguage;
        final isPremium = userStateProvider.isPremium;
        
        return Scaffold(
          appBar: AppBar(
            title: Text(AppStrings.get('settings_title')),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          ),
          body: ListView(
            children: [
              // 語言設置
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(AppStrings.get('language')),
                subtitle: Text(UserState.languageNames[currentLanguage] ?? currentLanguage),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showLanguageDialog(context),
              ),
          
              const Divider(),
              
              // 付費狀態（優先使用 Provider，向後兼容 AppConfig）
              ListTile(
                leading: Icon(
                  isPremium ? Icons.verified_user : Icons.lock,
                  color: isPremium ? Colors.amber : Colors.grey,
                ),
                title: Text(AppStrings.get('premium_status')),
                subtitle: Text(
                  isPremium 
                      ? AppStrings.get('premium_user') 
                      : AppStrings.get('free_user'),
                ),
                trailing: isPremium
                    ? null
                    : const Icon(Icons.chevron_right),
                onTap: isPremium
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PremiumScreen(),
                          ),
                        );
                      },
              ),
          
          const Divider(),
          
          // 關於
          ListTile(
            leading: const Icon(Icons.info),
            title: Text(AppStrings.get('about')),
            subtitle: Text('${AppStrings.get('version')} ${AppConfig.appVersion}'),
              ),
            ],
          ),
        );
      },
    );
  }
}

