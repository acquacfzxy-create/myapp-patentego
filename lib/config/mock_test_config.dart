/// 模擬考試配置
class MockTestConfig {
  /// 總題數
  static const int totalQuestions = 30;
  
  /// 時間限制（分鐘）
  static const int timeLimitMinutes = 20;
  
  /// 最多錯誤題數（超過則不及格）
  static const int maxErrors = 3;
  
  /// 時間限制轉換為秒
  static int get timeLimitSeconds => timeLimitMinutes * 60;
}
