import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;

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

  /// 關鍵詞 JSON 字符串（可選，用於存儲重點詞彙解析數據）
  final String? keywordsJson;

  Question({
    required this.id,
    this.imageName,
    required this.answer,
    required this.translations,
    required this.explanations,
    this.chapter,
    this.keywordsJson,
  });

  /// 從數據庫查詢結果構建 Question 對象
  /// [map] 包含 id, img, answer, question, explanation, lang 等字段
  /// 健壯處理：所有字段都可能為null，確保不會崩潰
  factory Question.fromMap(Map<String, dynamic> map, String lang) {
    try {
      // 🔍 強制修復：使用 ?.toString() 確保即便數據庫返回的不是 String 也能強轉
      final keywordsJsonValue = map['keywords_json']?.toString();

      // 處理翻譯：確保包含意大利語原文
      final translations = <String, String>{};
      final explanations = <String, String>{};

      // 優先使用處理後的 question 字段（翻譯）
      final questionText = map['question'] as String? ?? '';
      if (questionText.isNotEmpty) {
        translations[lang] = questionText;
      }

      // 確保包含意大利語原文（從 it_text）
      final itText = map['it_text'] as String?;
      if (itText != null && itText.isNotEmpty) {
        translations['it'] = itText;
      } else if (translations.isEmpty) {
        // 如果沒有意語原文，至少確保有一個值
        translations['it'] = questionText.isNotEmpty ? questionText : '';
      }

      // 處理解析
      final explanationText = map['explanation'] as String? ?? '';
      if (explanationText.isNotEmpty) {
        explanations[lang] = explanationText;
      }

      final question = Question(
        id: map['id'] as String? ?? '',
        imageName: map['img'] as String?,
        answer: (map['answer'] as int? ?? 0) == 1,
        translations: translations,
        explanations: explanations,
        chapter: map['chapter'] as int?, // 數據庫中可能沒有此字段，會返回 null（已移除章節功能）
        keywordsJson: keywordsJsonValue, // 🔍 強制使用 ?.toString() 確保類型轉換
      );

      // 🔍 打印驗證：確認對象創建成功

      return question;
    } catch (e) {
      // 如果解析失敗，返回一個安全的默認值

      // 🔍 強制修復：使用 ?.toString() 確保即便數據庫返回的不是 String 也能強轉
      final keywordsJsonValue = map['keywords_json']?.toString();

      // 錯誤恢復：確保至少包含基本數據
      final translations = <String, String>{};
      final explanations = <String, String>{};

      final questionText = map['question']?.toString() ?? '';
      if (questionText.isNotEmpty) {
        translations[lang] = questionText;
      }

      final itText = map['it_text']?.toString();
      if (itText != null && itText.isNotEmpty) {
        translations['it'] = itText;
      } else if (translations.isEmpty) {
        translations['it'] = questionText.isNotEmpty ? questionText : '';
      }

      final explanationText = map['explanation']?.toString() ?? '';
      if (explanationText.isNotEmpty) {
        explanations[lang] = explanationText;
      }

      final question = Question(
        id: map['id']?.toString() ?? 'unknown',
        imageName: map['img']?.toString(),
        answer: false,
        translations: translations,
        explanations: explanations,
        chapter: null,
        keywordsJson: keywordsJsonValue, // 🔍 強制使用 ?.toString() 確保類型轉換
      );

      // 🔍 打印驗證：確認對象創建成功（即使發生錯誤）

      return question;
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

    // 🔍 強制修復：使用 ?.toString() 確保即便數據庫返回的不是 String 也能強轉
    final keywordsJsonValue = map['keywords_json']?.toString();

    final question = Question(
      id: map['id'] as String,
      imageName: map['img'] as String?,
      answer: (map['answer'] as int) == 1,
      translations: translations,
      explanations: explanations,
      chapter: map['chapter'] as int?,
      keywordsJson: keywordsJsonValue, // 🔍 強制使用 ?.toString() 確保類型轉換
    );

    // 🔍 打印驗證：確認對象創建成功

    return question;
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
      keywordsJson: keywordsJson ?? other.keywordsJson, // 合併關鍵詞 JSON
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

  /// 獲取重點詞彙列表（從 keywordsJson 解析，支持多語言）
  /// [languageCode] 目標語言代碼（如 'zh', 'en', 'ru', 'it'）
  /// 如果 keywordsJson 為空或解析失敗，返回空列表
  /// 支持兩種格式：
  /// 1. 舊格式（扁平）：[{"it": "word", "zh": "詞彙"}, ...]
  /// 2. 新格式（多語言嵌套）：{"it": [{"it": "word", "zh": "詞彙"}, ...], "zh": [...], "en": [...]}
  List<Map<String, String>> getKeyWords(String languageCode) {
    // 🔍 調試：打印正在解析的 JSON
    if (kDebugMode) {
    }

    // 檢查 keywordsJson 是否為 null 或空字符串
    if (keywordsJson == null || keywordsJson!.trim().isEmpty) {
      if (kDebugMode) {
      }
      return [];
    }

    // 檢查是否為空數組的 JSON 字符串
    final trimmedJson = keywordsJson!.trim();
    if (trimmedJson == '[]' || trimmedJson == 'null') {
      if (kDebugMode) {
      }
      return [];
    }

    try {
      // 解析 JSON 字符串
      final decoded = jsonDecode(trimmedJson);

      // 處理新格式（多語言嵌套）：{"it": [...], "zh": [...], "en": [...]}
      if (decoded is Map) {
        // 嘗試獲取目標語言的關鍵詞列表
        List<dynamic>? targetLanguageList;

        // 優先使用目標語言
        if (decoded.containsKey(languageCode)) {
          final langData = decoded[languageCode];
          if (langData is List) {
            targetLanguageList = langData;
          }
        }

        // 如果目標語言不存在，嘗試使用備用語言（意大利語 > 英語 > 第一個可用語言）
        if (targetLanguageList == null) {
          // 嘗試意大利語
          if (decoded.containsKey('it')) {
            final itData = decoded['it'];
            if (itData is List) {
              targetLanguageList = itData;
            }
          }
        }

        if (targetLanguageList == null) {
          // 嘗試英語
          if (decoded.containsKey('en')) {
            final enData = decoded['en'];
            if (enData is List) {
              targetLanguageList = enData;
            }
          }
        }

        if (targetLanguageList == null) {
          // 使用第一個可用的語言
          for (final value in decoded.values) {
            if (value is List) {
              targetLanguageList = value;
              break;
            }
          }
        }

        // 轉換為 Map<String, String> 列表
        if (targetLanguageList != null) {
          final result = <Map<String, String>>[];
          for (final item in targetLanguageList) {
            if (item is Map) {
              try {
                final keywordMap = <String, String>{};
                item.forEach((key, value) {
                  keywordMap[key.toString()] = value.toString();
                });
                // 確保至少包含一個有效的鍵值對
                if (keywordMap.isNotEmpty) {
                  result.add(keywordMap);
                }
              } catch (e) {
                if (kDebugMode) {
                }
              }
            }
          }

          if (kDebugMode) {
          }

          return result;
        }
      }

      // 處理扁平格式：[{"it": "word", "zh": "...", "en": "...", "ru": "...", ...}, ...]
      if (decoded is List) {
        final result = <Map<String, String>>[];
        for (final item in decoded) {
          if (item is Map) {
            try {
              final keywordMap = <String, String>{};
              item.forEach((key, value) {
                keywordMap[key.toString()] = value.toString();
              });

              // 確保包含意大利語（原始語言）
              if (!keywordMap.containsKey('it') || keywordMap['it']!.isEmpty) {
                continue; // 跳過沒有意大利語的項
              }

              // 語言降級邏輯：目標語言 → 英語 → 中文 → 意大利語
              String? translation;

              // 1. 優先使用目標語言
              if (keywordMap.containsKey(languageCode) && keywordMap[languageCode]!.isNotEmpty) {
                translation = keywordMap[languageCode];
              }
              // 2. 降級到英語
              else if (keywordMap.containsKey('en') && keywordMap['en']!.isNotEmpty) {
                translation = keywordMap['en'];
              }
              // 3. 降級到中文
              else if (keywordMap.containsKey('zh') && keywordMap['zh']!.isNotEmpty) {
                translation = keywordMap['zh'];
              }
              // 4. 最後降級到意大利語（如果都沒有，至少顯示原始語言）
              else {
                translation = keywordMap['it'];
              }

              // 構建結果映射：包含意大利語和翻譯
              final targetMap = <String, String>{
                'it': keywordMap['it']!,
                languageCode: translation ?? keywordMap['it']!,
              };

              result.add(targetMap);
            } catch (e) {
              if (kDebugMode) {
              }
            }
          }
        }

        if (kDebugMode) {
        }

        return result;
      }

      // 格式不匹配
      if (kDebugMode) {
      }
      return [];
    } catch (e) {
      // 如果 JSON 解析失敗，返回空列表（不會導致頁面報錯）
      if (kDebugMode) {
        if (trimmedJson.length > 200) {
        } else {
        }
      }
      return [];
    }
  }

  /// 獲取重點詞彙列表（向後兼容的 getter，使用默認語言 'zh'）
  /// 注意：建議使用 getKeyWords(String languageCode) 方法以支持多語言
  @Deprecated('請使用 getKeyWords(String languageCode) 方法以支持多語言')
  List<Map<String, String>> get keyWords {
    return getKeyWords('zh');
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
      'keywords_json': keywordsJson,
    };
  }

  @override
  String toString() {
    return 'Question(id: $id, answer: $answer, translations: ${translations.keys})';
  }
}

