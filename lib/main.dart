import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/language_selection_screen.dart';
import 'services/database_service.dart';
import 'config/app_config.dart';
import 'config/app_strings.dart';
import 'providers/user_state_provider.dart';

void main() async {
  // 確保 Flutter 綁定已初始化（必須在所有異步操作之前調用）
  WidgetsFlutterBinding.ensureInitialized();
  
  // 設置系統UI樣式
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 嘗試初始化數據庫（即使失敗也不阻止應用啟動）
  try {
    print('🔄 [Database] 開始初始化數據庫...');
    await DatabaseService.init();
    print('✅ [Database] 數據庫初始化成功');
  } catch (e, stackTrace) {
    print('❌ [Database] 數據庫初始化失敗: $e');
    print('📋 [Database] 錯誤堆棧: $stackTrace');
    // 即使數據庫初始化失敗，也繼續啟動應用
    // 錯誤信息會在應用的全局變量中保存，供後續使用
    DatabaseService.initError = e.toString();
  }
  
  // 加載付費狀態（從本地存儲，未來會遷移到 Provider）
  try {
    await AppConfig.loadPremiumStatus();
    print('✅ [Config] 配置加載成功');
  } catch (e) {
    print('⚠️ [Config] 配置加載失敗: $e');
  }
  
  // 初始化多語言（設置默認語言，Provider 會覆蓋）
  AppStrings.setLanguage('zh');
  
  // 啟動應用（使用 Provider 管理全局狀態）
  runApp(
    ChangeNotifierProvider(
      create: (_) => UserStateProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 監聽 UserStateProvider 的變化，自動重建 MaterialApp
    return Consumer<UserStateProvider>(
      builder: (context, userStateProvider, child) {
        // 確保 AppStrings 與 Provider 同步（向後兼容舊代碼）
        final currentLang = userStateProvider.currentLanguage;
        if (AppStrings.getLanguage() != currentLang) {
          AppStrings.setLanguage(currentLang);
        }

        // 判斷是否為 RTL 語言（從右向左）
        final isRTL = currentLang == 'ur' || currentLang == 'pa';
        
        return Directionality(
          textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
          child: MaterialApp(
            title: '義大利駕照測驗',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
              useMaterial3: true,
            ),
            // 根據是否選擇過語言決定初始頁面
            home: FutureBuilder<bool>(
              future: UserStateProvider.hasSelectedLanguage(),
              builder: (context, snapshot) {
                // 如果還在加載，顯示空白頁面（避免閃爍）
                if (!snapshot.hasData) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                
                // 如果已經選擇過語言，進入首頁；否則顯示語言選擇頁
                return snapshot.data == true
                    ? const HomeScreen()
                    : const LanguageSelectionScreen();
              },
            ),
            debugShowCheckedModeBanner: false,
          ),
        );
      },
    );
  }
}

