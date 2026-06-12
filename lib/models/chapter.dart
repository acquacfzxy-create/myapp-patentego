/// 章節模型
/// 用於管理意大利駕照考試的章節信息
class ChapterModel {
  /// 章節ID（1-25）
  final int id;
  
  /// 章節標題（意大利語）
  final String titleIt;
  
  /// 章節標題翻譯（多語言）
  final Map<String, String> titleTranslations;
  
  /// 是否為重點章節（前15章為true，後10章為false）
  final bool isPrincipal;
  
  const ChapterModel({
    required this.id,
    required this.titleIt,
    required this.titleTranslations,
    required this.isPrincipal,
  });
  
  /// 獲取指定語言的章節標題
  /// [lang] 語言代碼（如 'zh', 'en', 'ru' 等）
  String getTitle(String lang) {
    return titleTranslations[lang] ?? titleIt;
  }
  
  /// 從Map創建ChapterModel
  factory ChapterModel.fromMap(Map<String, dynamic> map) {
    return ChapterModel(
      id: map['id'] as int,
      titleIt: map['titleIt'] as String,
      titleTranslations: Map<String, String>.from(map['titleTranslations'] as Map),
      isPrincipal: map['isPrincipal'] as bool,
    );
  }
  
  /// 轉換為Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titleIt': titleIt,
      'titleTranslations': titleTranslations,
      'isPrincipal': isPrincipal,
    };
  }
}

