import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../config/app_strings.dart';

/// 會員訂閱介紹頁面
/// 用於展示付費功能和引導用戶訂閱
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('upgrade_premium')),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 會員圖標
            const Icon(
              Icons.workspace_premium,
              size: 100,
              color: Colors.amber,
            ),
            const SizedBox(height: 24),
            
            // 標題
            Text(
              AppStrings.get('upgrade_to_premium'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            
            // 會員功能列表
            _buildFeatureItem(Icons.lock_open, AppStrings.get('unlock_all_chapters')),
            _buildFeatureItem(Icons.star, AppStrings.get('ad_free_experience')),
            _buildFeatureItem(Icons.cloud_download, AppStrings.get('cloud_sync')),
            _buildFeatureItem(Icons.analytics, AppStrings.get('detailed_stats')),
            
            const Spacer(),
            
            // 訂閱按鈕
            ElevatedButton(
              onPressed: () {
                // 在實際應用中，這裡應該調用支付 SDK（如 In-App Purchase）
                // 支付成功後調用 AppConfig.setPremium(true)
                
                // 這裡僅作為演示，直接設置為付費會員
                AppConfig.setPremium(true);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppStrings.get('upgraded_to_premium')),
                    backgroundColor: Colors.green,
                  ),
                );
                
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                AppStrings.get('subscribe_now'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 恢復購買按鈕
            TextButton(
              onPressed: () {
                // 在實際應用中，這裡應該調用支付 SDK 的恢復購買功能
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppStrings.get('restore_purchase_demo'))),
                );
              },
              child: Text(AppStrings.get('restore_purchase')),
            ),
          ],
        ),
      ),
    );
  }

  /// 構建功能列表項
  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue),
          const SizedBox(width: 16),
          Text(
            text,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}

