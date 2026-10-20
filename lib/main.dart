import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'screens/splash_bootstrap.dart';
import 'screens/home_screen.dart';
import 'screens/web_app_screen.dart';
import 'services/database_service.dart';
import 'services/firebase_status.dart';
import 'services/iap_service.dart';
import 'services/voice_pack_service.dart';
import 'config/app_locales.dart';
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
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserStateProvider()),
        // App 级購買協調器：啟動即監聽 purchaseStream，不依賴訂閱頁生命週期。
        ChangeNotifierProvider<IapService>(
          lazy: false,
          create: (context) {
            // 先取得实例再捕获，App 级服务不持有 Provider 的 BuildContext。
            final userState = context.read<UserStateProvider>();
            final service = IapService();
            // 续订等待仅限 Android Play Billing；Web 等平台不注入，保持原有到期判定。
            if (service.supportsRenewalChecks) {
              userState.attachRenewalChecker(service.checkRenewal);
            }
            unawaited(service.start(
              onEntitlementActive: userState.activateVipFromVerifiedPurchase,
              onResumed: userState.handleAppResumed,
            ));
            return service;
          },
        ),
      ],
      child: const MyApp(),
    ),
  );

  // 背景恢復已下載語音包並刷新目錄，不延遲離線題庫啟動。
  if (!kIsWeb) unawaited(_initializeVoicePacks());
}

Future<void> _initializeVoicePacks() async {
  try {
    await VoicePackService.instance.initialize();
  } catch (_) {
    // 雲端不可用時保留系統 TTS 備援，語音包頁可稍後手動重試。
  }
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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshDailyCounters());
    }
  }

  Future<void> _refreshDailyCounters() async {
    try {
      await context.read<UserStateProvider>().checkAndResetDailyCounters();
    } catch (_) {
      // 生命週期刷新失敗不阻斷 App 恢復前景。
    }
  }

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
        final themeMode = userStateProvider.themeMode;
        final isDarkMode = themeMode == AppThemeMode.night;
        final isRetroMode = themeMode == AppThemeMode.retro;

        return MaterialApp(
          title: AppStrings.getWithLanguage(currentLang, 'app_title'),
          // 让系统组件跟随界面语言；ur 的 RTL 同时由 Localizations 提供。
          locale: AppLocales.localeFor(currentLang),
          supportedLocales: AppLocales.supportedLocales,
          localizationsDelegates: AppLocales.delegates,
          theme: isRetroMode
              ? AppTheme.retroTheme(language: currentLang)
              : kIsWeb
                  ? AppTheme.webTheme()
                  : AppTheme.lightTheme(language: currentLang),
          darkTheme: kIsWeb
              ? AppTheme.webTheme(dark: true)
              : AppTheme.darkTheme(language: currentLang),
          themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    isDarkMode ? Brightness.light : Brightness.dark,
                // iOS 只认 statusBarBrightness（指页面底色的明暗，与图标亮度相反）。
                statusBarBrightness:
                    isDarkMode ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: isDarkMode
                    ? (AppTheme.usesRoadPalette
                        ? AppTheme.roadNightPage
                        : AppTheme.nightPage)
                    : isRetroMode
                        ? AppTheme.retroPage
                        : AppTheme.usesRoadPalette
                            ? AppTheme.roadPage
                            : Colors.white,
                systemNavigationBarIconBrightness:
                    isDarkMode ? Brightness.light : Brightness.dark,
              ),
              child: Directionality(
                textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          // 注册路由观察者
          navigatorObservers: [routeObserver],
          home: kIsWeb ? const WebAppScreen() : const SplashBootstrap(),
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
