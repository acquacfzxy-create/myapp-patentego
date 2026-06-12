/// 用戶狀態模型
/// 用於管理用戶的全局設置和狀態
class UserState {
  /// 是否為 VIP 會員
  final bool isVip;
  
  /// 當前選中的語言代碼（如 'zh', 'it', 'en'）
  final String currentLanguage;
  
  /// 支持的所有語言列表（已不再對外提供義大利語作為 UI 語言）
  static const List<String> supportedLanguages = ['zh', 'en', 'ur', 'pa', 'ru', 'uk'];
  
  /// 語言顯示名稱映射（移除義大利語鍵，保留核心數據層中的 it 文本不變）
  static const Map<String, String> languageNames = {
    'zh': '中文',
    'en': 'English',
    'ur': 'اردو',
    'pa': 'ਪੰਜਾਬੀ',
    'ru': 'Русский',
    'uk': 'Українська',
  };

  const UserState({
    this.isVip = false,
    this.currentLanguage = 'zh',
  });

  /// 複製並更新字段
  UserState copyWith({
    bool? isVip,
    String? currentLanguage,
  }) {
    return UserState(
      isVip: isVip ?? this.isVip,
      currentLanguage: currentLanguage ?? this.currentLanguage,
    );
  }

  /// 從本地存儲恢復（未來可擴展為 SharedPreferences）
  /// 向後兼容：同時讀取 isVip 和 isPremium
  factory UserState.fromMap(Map<String, dynamic> map) {
    // 向後兼容：同時讀 isVip 與 isPremium
    final dynamic vipValue = map['isVip'] ?? map['isPremium'];
    return UserState(
      isVip: vipValue is bool ? vipValue : false,
      currentLanguage: map['currentLanguage'] as String? ?? 'zh',
    );
  }

  /// 轉換為 Map（用於數據持久化）
  Map<String, dynamic> toMap() {
    return {
      'isVip': isVip,
      'currentLanguage': currentLanguage,
    };
  }

  /// 獲取當前語言的顯示名稱
  String get currentLanguageName {
    return languageNames[currentLanguage] ?? currentLanguage;
  }
}

