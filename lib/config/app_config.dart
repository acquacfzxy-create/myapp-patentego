/// 應用全局配置（僅保留常量）
class AppConfig {
  /// 免費用戶可訪問的章節數量限制
  static const int freeChapterLimit = 2;

  /// 檢查章節是否被鎖定（需要付費）
  /// [chapterNumber] 章節編號（從1開始）
  /// [isVip] 用戶是否為 VIP 會員
  /// 返回 true 表示該章節被鎖定，需要付費才能訪問
  static bool isChapterLocked(int chapterNumber, {required bool isVip}) {
    // 如果章節數 > 免費限制 且 用戶不是 VIP 會員，則鎖定
    return chapterNumber > freeChapterLimit && !isVip;
  }

  /// 應用版本號
  static const String appVersion = '1.1.2';

  /// App Store Connect / Google Play Console 中的自動續訂月訂閱商品 ID
  static const String monthlySubscriptionProductId = 'patentego_vip_monthly';

  static const bool requireServerPurchaseVerification = true;

  /// Enable only after backend deployment and Play license testing pass.
  static const bool playBillingEnabled =
      bool.fromEnvironment('PLAY_BILLING_ENABLED');
  static const String purchaseVerificationUrl =
      'https://europe-west1-italy-patente-b.cloudfunctions.net/verifyPlaySubscription';

  /// iOS：与 Play 相同，仅在 verifyAppStoreSubscription 部署并通过沙盒测试后才开启。
  static const bool appStoreBillingEnabled =
      bool.fromEnvironment('APP_STORE_BILLING_ENABLED');
  static const String appStoreVerificationUrl =
      'https://europe-west1-italy-patente-b.cloudfunctions.net/verifyAppStoreSubscription';

  /// 删除账号（callable）：服务端删除云端数据与 Firebase Auth 账号。
  static const String deleteAccountUrl =
      'https://europe-west1-italy-patente-b.cloudfunctions.net/deleteAccount';

  /// 续订等待上限（内部测试值，待真机数据确认后调整）：同一账号、同一周期先前已确认
  /// 有效的权益，在 Play 原始到期时间之后最多暂时保留这么久，等待续订同步。
  static const Duration subscriptionRenewalGraceLimit = Duration(seconds: 90);

  /// 是否開啟調試模式
  static const bool debugMode = false;

  /// 合規頁面連結（GitHub Pages 由公開倉庫 linguapatente-legal 發布）
  static const String privacyPolicyUrl =
      'https://acquacfzxy-create.github.io/linguapatente-legal/privacy.html';
  static const String termsOfServiceUrl =
      'https://acquacfzxy-create.github.io/linguapatente-legal/terms.html';
  static const String supportContactUrl =
      'mailto:patentegoapp@gmail.com?subject=LinguaPatente%20Support';

  /// Google Play 订阅中心：直接打开本应用该订阅的管理 / 取消页面（Play 订阅政策要求的在线取消入口）。
  static const String playSubscriptionCenterUrl =
      'https://play.google.com/store/account/subscriptions'
      '?sku=$monthlySubscriptionProductId&package=com.patentego.app';

  /// App Store 订阅管理页（Apple 要求提供取消 / 管理订阅的入口）。
  static const String appStoreSubscriptionCenterUrl =
      'https://apps.apple.com/account/subscriptions';
}
