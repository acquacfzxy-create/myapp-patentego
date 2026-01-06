/// 應用全局配置
/// 管理付費狀態、功能開關等全局設置
class AppConfig {
  /// 是否為付費會員（全局變量）
  /// 在實際應用中，這個值應該從本地存儲或服務器獲取
  static bool isUserPremium = false;

  /// 免費用戶可訪問的章節數量限制
  static const int freeChapterLimit = 2;

  /// 檢查章節是否被鎖定（需要付費）
  /// [chapterNumber] 章節編號（從1開始）
  /// 返回 true 表示該章節被鎖定，需要付費才能訪問
  static bool isChapterLocked(int chapterNumber) {
    // 如果章節數 > 免費限制 且 用戶不是付費會員，則鎖定
    return chapterNumber > freeChapterLimit && !isUserPremium;
  }

  /// 設置付費狀態（用於測試或付費成功後調用）
  static void setPremium(bool premium) {
    isUserPremium = premium;
    // 在實際應用中，應該將這個狀態保存到本地存儲（如 SharedPreferences）
    // SharedPreferences.getInstance().then((prefs) {
    //   prefs.setBool('is_premium', premium);
    // });
  }

  /// 從本地存儲加載付費狀態（應用啟動時調用）
  static Future<void> loadPremiumStatus() async {
    // 在實際應用中，應該從本地存儲讀取
    // final prefs = await SharedPreferences.getInstance();
    // isUserPremium = prefs.getBool('is_premium') ?? false;
  }

  /// 應用版本號
  static const String appVersion = '1.0.0';

  /// 是否開啟調試模式
  static const bool debugMode = true;
}

