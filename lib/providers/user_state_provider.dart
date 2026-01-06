import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_state.dart';
import '../config/app_strings.dart';
import '../config/app_config.dart';
import '../services/database_service.dart';

/// 用户状态管理 Provider
/// 管理全局用户状态：语言、会员状态等
class UserStateProvider extends ChangeNotifier {
  // 当前用户状态
  UserState _userState = const UserState(
    isPremium: false,
    currentLanguage: 'zh',
  );

  // 已掌握的题目总数
  int _masteredCount = 0;

  // 获取当前用户状态
  UserState get userState => _userState;

  // 获取当前语言
  String get currentLanguage => _userState.currentLanguage;

  // 获取会员状态
  bool get isPremium => _userState.isPremium;

  // 获取已掌握的题目总数
  int get masteredCount => _masteredCount;

  /// 构造函数：从持久化存储加载初始状态
  UserStateProvider() {
    _loadUserState();
  }

  /// 从本地存储加载用户状态
  Future<void> _loadUserState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 从 SharedPreferences 加载语言
      final language = prefs.getString('current_language');
      
      // 从 SharedPreferences 加载会员状态
      final isPremium = prefs.getBool('is_premium') ?? false;
      
      // 如果保存了语言，使用保存的语言；否则使用默认值
      final currentLang = language ?? 'zh';
      
      _userState = _userState.copyWith(
        currentLanguage: currentLang,
        isPremium: isPremium,
      );
      
      // 同步更新 AppStrings（向后兼容）
      AppStrings.setLanguage(currentLang);
      
      // 同步更新 AppConfig（向后兼容）
      AppConfig.setPremium(isPremium);
      
      // 初始化掌握度统计
      await refreshMasteryStats();
    } catch (e) {
      // 如果加载失败，使用默认值
      print('⚠️ [UserStateProvider] 加载用户状态失败: $e');
      _userState = _userState.copyWith(
        currentLanguage: 'zh',
        isPremium: false,
      );
      _masteredCount = 0;
    }
  }

  /// 检查是否已经选择过语言（是否首次启动）
  static Future<bool> hasSelectedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey('current_language');
    } catch (e) {
      return false;
    }
  }

  /// 切换语言
  /// [language] 新的语言代码
  Future<void> changeLanguage(String language) async {
    if (!UserState.supportedLanguages.contains(language)) {
      return;
    }

    // 更新用户状态
    _userState = _userState.copyWith(currentLanguage: language);

    // 同步更新 AppStrings（保持兼容性）
    AppStrings.setLanguage(language);

    // 保存到本地存储
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_language', language);
    } catch (e) {
      print('⚠️ [UserStateProvider] 保存语言失败: $e');
    }

    // 通知所有监听者（触发 UI 更新）
    notifyListeners();
  }

  /// 设置会员状态
  /// [premium] 是否为会员
  Future<void> setPremium(bool premium) async {
    _userState = _userState.copyWith(isPremium: premium);

    // 同步更新 AppConfig（向后兼容，保持一致性）
    AppConfig.setPremium(premium);

    // 保存到本地存储
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_premium', premium);
    } catch (e) {
      print('⚠️ [UserStateProvider] 保存会员状态失败: $e');
    }

    // 通知所有监听者
    notifyListeners();
  }

  /// 检查章节是否被锁定（需要付费）
  /// [chapterNumber] 章节编号（从1开始）
  /// 返回 true 表示该章节被锁定，需要付费才能访问
  bool isChapterLocked(int chapterNumber) {
    // 如果章节数 > 免费限制 且 用户不是付费会员，则锁定
    return chapterNumber > AppConfig.freeChapterLimit && !_userState.isPremium;
  }

  /// 刷新掌握度统计（从数据库查询已掌握的总题数）
  /// 调用此方法会更新 _masteredCount 并触发 notifyListeners()
  Future<void> refreshMasteryStats() async {
    try {
      _masteredCount = await DatabaseService.getMasteredCount();
      notifyListeners();
    } catch (e) {
      print('⚠️ [UserStateProvider] 刷新掌握度统计失败: $e');
      // 如果查询失败，保持当前值不变
    }
  }

  /// 獲取全局掌握百分比
  /// 返回當前用戶對整個題庫的總掌握百分比（0.0 - 1.0）
  Future<double> getTotalMasteryPercentage() async {
    return await DatabaseService.getTotalMasteryPercentage();
  }

  /// 更新用户状态（批量更新）
  Future<void> updateUserState({
    bool? isPremium,
    String? currentLanguage,
  }) async {
    _userState = _userState.copyWith(
      isPremium: isPremium,
      currentLanguage: currentLanguage,
    );

    // 如果语言改变，同步更新 AppStrings
    if (currentLanguage != null) {
      AppStrings.setLanguage(currentLanguage);
    }

    // 保存到本地存储
    try {
      final prefs = await SharedPreferences.getInstance();
      if (currentLanguage != null) {
        await prefs.setString('current_language', currentLanguage);
      }
      if (isPremium != null) {
        await prefs.setBool('is_premium', isPremium);
      }
    } catch (e) {
      print('⚠️ [UserStateProvider] 保存用户状态失败: $e');
    }

    notifyListeners();
  }
}
