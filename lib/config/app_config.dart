/// 應用全局配置（僅保留常量）
class AppConfig {
  /// 免費用戶可訪問的章節數量限制
  static const int freeChapterLimit = 3;

  /// 檢查章節是否被鎖定（需要付費）
  /// [chapterNumber] 章節編號（從1開始）
  /// [isVip] 用戶是否為 VIP 會員
  /// 返回 true 表示該章節被鎖定，需要付費才能訪問
  static bool isChapterLocked(int chapterNumber, {required bool isVip}) {
    // 如果章節數 > 免費限制 且 用戶不是 VIP 會員，則鎖定
    return chapterNumber > freeChapterLimit && !isVip;
  }

  /// 應用版本號
  static const String appVersion = '1.0.0';

  /// App Store Connect / Google Play Console 中的自動續訂月訂閱商品 ID
  static const String monthlySubscriptionProductId = 'patentego_vip_monthly';

  /// 正式後端驗證完成前保持 false，讓 TestFlight / sandbox 可先測購買流程。
  /// 上架正式版前，接入可信後端驗證後改為 true。
  static const bool requireServerPurchaseVerification = false;

  /// 是否開啟調試模式
  static const bool debugMode = false;

  /// 合規頁面連結（GitHub Pages 從 docs/ 發布時對應 docs/privacy.html 與 docs/terms.html）
  static const String privacyPolicyUrl =
      'https://acquacfzxy-create.github.io/myapp-patentego/privacy.html';
  static const String termsOfServiceUrl =
      'https://acquacfzxy-create.github.io/myapp-patentego/terms.html';
  static const String supportContactUrl =
      'mailto:patentegoapp@gmail.com?subject=PatenteGo%20Support';
}
