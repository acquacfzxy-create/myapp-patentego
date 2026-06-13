import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'screens/splash_bootstrap.dart';
import 'screens/home_screen.dart';
import 'services/database_service.dart';
import 'services/firebase_status.dart';
import 'config/app_strings.dart';
import 'config/app_theme.dart';
import 'config/route_observer.dart';
import 'providers/user_state_provider.dart';

void main() async {
  // 確保 Flutter 綁定已初始化（必須在所有異步操作之前調用）
  WidgetsFlutterBinding.ensureInitialized();
  _registerThirdPartyLicenses();

  // 初始化 Firebase
  try {
    await Firebase.initializeApp();
    FirebaseStatus.markInitialized();
  } catch (e) {
    FirebaseStatus.markUnavailable(e);
    // Firebase 初始化失敗時不中斷離線題庫功能；後續登入/同步功能會自行報錯。
  }

  // 設置系統UI樣式
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 嘗試初始化數據庫（即使失敗也不阻止應用啟動）
  try {
    await DatabaseService.init();
  } catch (e) {
    // 即使數據庫初始化失敗，也繼續啟動應用
    // 錯誤信息會在應用的全局變量中保存，供後續使用
    DatabaseService.initError = e.toString();
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

void _registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['QuizPatenteB road sign images'],
      '''
MIT License

Copyright (c) 2023 Edoardo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''',
    );
  });
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
        final isRTL = currentLang == 'ur';

        return MaterialApp(
          title: AppStrings.getWithLanguage(currentLang, 'app_title'),
          theme: AppTheme.lightTheme(),
          builder: (context, child) {
            return Directionality(
              textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
          // 注册路由观察者
          navigatorObservers: [routeObserver],
          home: const SplashBootstrap(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
