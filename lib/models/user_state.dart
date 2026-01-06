/// 用戶狀態模型
/// 用於管理用戶的全局設置和狀態
class UserState {
  /// 是否為付費會員
  final bool isPremium;
  
  /// 當前選中的語言代碼（如 'zh', 'it', 'en'）
  final String currentLanguage;
  
  /// 支持的所有語言列表
  static const List<String> supportedLanguages = ['zh', 'it', 'en', 'ur', 'pa', 'ru', 'uk'];
  
  /// 語言顯示名稱映射
  static const Map<String, String> languageNames = {
    'zh': '中文',
    'it': 'Italiano',
    'en': 'English',
    'ur': 'اردو',
    'pa': 'ਪੰਜਾਬੀ',
    'ru': 'Русский',
    'uk': 'Українська',
  };

  const UserState({
    this.isPremium = false,
    this.currentLanguage = 'zh',
  });

  /// 複製並更新字段
  UserState copyWith({
    bool? isPremium,
    String? currentLanguage,
  }) {
    return UserState(
      isPremium: isPremium ?? this.isPremium,
      currentLanguage: currentLanguage ?? this.currentLanguage,
    );
  }

  /// 從本地存儲恢復（未來可擴展為 SharedPreferences）
  factory UserState.fromMap(Map<String, dynamic> map) {
    return UserState(
      isPremium: map['isPremium'] as bool? ?? false,
      currentLanguage: map['currentLanguage'] as String? ?? 'zh',
    );
  }

  /// 轉換為 Map（用於數據持久化）
  Map<String, dynamic> toMap() {
    return {
      'isPremium': isPremium,
      'currentLanguage': currentLanguage,
    };
  }

  /// 獲取當前語言的顯示名稱
  String get currentLanguageName {
    return languageNames[currentLanguage] ?? currentLanguage;
  }
}

