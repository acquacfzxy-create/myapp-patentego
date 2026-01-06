/// 題目數據模型
/// 用於存儲題目的完整信息，支持多語言擴展
class Question {
  /// 題目唯一標識符
  final String id;
  
  /// 圖片名稱（相對路徑，如 "/img_sign/550.png"）
  final String? imageName;
  
  /// 正確答案：true = 正確，false = 錯誤
  final bool answer;
  
  /// 多語言題目內容映射
  /// key: 語言代碼（如 'zh', 'it', 'en'）
  /// value: 該語言下的題目文本
  final Map<String, String> translations;
  
  /// 多語言解析內容映射
  /// key: 語言代碼（如 'zh', 'it', 'en'）
  /// value: 該語言下的解析文本
  final Map<String, String> explanations;
  
  /// 章節ID（可選，用於分類題目）
  final int? chapter;

  Question({
    required this.id,
    this.imageName,
    required this.answer,
    required this.translations,
    required this.explanations,
    this.chapter,
  });

  /// 從數據庫查詢結果構建 Question 對象
  /// [map] 包含 id, img, answer, question, explanation, lang 等字段
  /// 健壯處理：所有字段都可能為null，確保不會崩潰
  factory Question.fromMap(Map<String, dynamic> map, String lang) {
    try {
      return Question(
        id: map['id'] as String? ?? '',
        imageName: map['img'] as String?,
        answer: (map['answer'] as int? ?? 0) == 1,
        translations: {lang: map['question'] as String? ?? ''},
        explanations: {lang: map['explanation'] as String? ?? ''},
        chapter: map['chapter'] as int?, // 數據庫中可能沒有此字段，會返回 null（已移除章節功能）
      );
    } catch (e) {
      // 如果解析失敗，返回一個安全的默認值
      return Question(
        id: map['id']?.toString() ?? 'unknown',
        imageName: map['img']?.toString(),
        answer: false,
        translations: {lang: map['question']?.toString() ?? ''},
        explanations: {lang: map['explanation']?.toString() ?? ''},
        chapter: null,
      );
    }
  }

  /// 從數據庫查詢結果構建 Question 對象，支持同時包含意大利語和翻譯語言
  /// [map] 包含 id, img, answer, question (意大利語), explanation (意大利語), 
  ///       question_trans (翻譯語言), explanation_trans (翻譯語言) 等字段
  /// [itLang] 意大利語語言代碼，默認為 'it'
  /// [translationLang] 翻譯語言代碼
  factory Question.fromMapWithTranslation(
    Map<String, dynamic> map, 
    String itLang, 
    String translationLang,
  ) {
    final translations = <String, String>{};
    final explanations = <String, String>{};
    
    // 添加意大利語內容（如果存在且不為空）
    final itQuestion = map['question'] as String?;
    if (itQuestion != null && itQuestion.isNotEmpty) {
      translations[itLang] = itQuestion;
    }
    final itExplanation = map['explanation'] as String?;
    if (itExplanation != null && itExplanation.isNotEmpty) {
      explanations[itLang] = itExplanation;
    }
    
    // 添加翻譯語言內容（如果存在且不為空）
    final transQuestion = map['question_trans'] as String?;
    if (transQuestion != null && transQuestion.isNotEmpty) {
      translations[translationLang] = transQuestion;
    }
    final transExplanation = map['explanation_trans'] as String?;
    if (transExplanation != null && transExplanation.isNotEmpty) {
      explanations[translationLang] = transExplanation;
    }
    
    return Question(
      id: map['id'] as String,
      imageName: map['img'] as String?,
      answer: (map['answer'] as int) == 1,
      translations: translations,
      explanations: explanations,
      chapter: map['chapter'] as int?,
    );
  }

  /// 合併多語言數據（當從數據庫獲取多條記錄時使用）
  /// [other] 另一個語言的 Question 對象
  Question mergeLanguages(Question other) {
    return Question(
      id: id,
      imageName: imageName ?? other.imageName,
      answer: answer,
      translations: {...translations, ...other.translations},
      explanations: {...explanations, ...other.explanations},
      chapter: chapter ?? other.chapter,
    );
  }

  /// 獲取指定語言的題目內容
  String? getQuestionText(String lang) {
    return translations[lang];
  }

  /// 獲取指定語言的解析內容
  String? getExplanationText(String lang) {
    return explanations[lang];
  }

  /// 轉換為 Map（用於數據持久化）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imageName': imageName,
      'answer': answer ? 1 : 0,
      'translations': translations,
      'explanations': explanations,
      'chapter': chapter,
    };
  }

  @override
  String toString() {
    return 'Question(id: $id, answer: $answer, translations: ${translations.keys})';
  }
}

