# 多語言動態顯示重構完成報告

**重構時間**: 2024年12月
**目標**: 支持多語言關鍵詞實時動態顯示

---

## ✅ 已完成的重構

### 1. Question 模型優化

#### 優化 `getKeyWords()` 方法
- **位置**: `lib/models/question.dart`
- **改進**: 優化扁平格式的語言提取邏輯，實現智能降級

#### 語言降級邏輯
```dart
// 降級順序：目標語言 → 英語 → 中文 → 意大利語
1. 優先使用目標語言（如 'ru', 'uk', 'pa', 'ur'）
2. 如果目標語言缺失，降級到英語（'en'）
3. 如果英語也缺失，降級到中文（'zh'）
4. 最後降級到意大利語（'it'）- 原始語言
```

#### 數據格式支持
- **扁平格式**: `[{"it": "word", "zh": "...", "en": "...", "ru": "...", ...}]`
- **多語言嵌套格式**: `{"it": [...], "zh": [...], "en": [...]}`（已支持）

---

### 2. 語言代碼映射確認

#### App 內部語言代碼
```dart
// lib/models/user_state.dart
static const List<String> supportedLanguages = [
  'zh',  // 中文
  'it',  // 意大利語
  'en',  // 英文
  'ur',  // 烏爾都語
  'pa',  // 旁遮普語
  'ru',  // 俄語
  'uk',  // 烏克蘭語
];
```

#### 數據庫 JSON 鍵名
- 與 App 內部語言代碼完全一致
- 格式：`{"it": "...", "zh": "...", "en": "...", "ru": "...", "uk": "...", "pa": "...", "ur": "..."}`

✅ **映射確認**: App 內部語言代碼與數據庫 JSON 鍵名一一對應

---

### 3. QuestionWidget 實時響應

#### 使用 `context.watch` 實時監聽
- **位置**: `lib/widgets/question_widget.dart`
- **變更**: 從 `Provider.of<UserStateProvider>(context, listen: false)` 改為 `context.watch<UserStateProvider>()`

#### 關鍵改進點

**1. `build()` 方法**
```dart
// 之前：不會響應語言變化
final userStateProvider = Provider.of<UserStateProvider>(context, listen: false);
final currentLang = userStateProvider.currentLanguage;

// 現在：實時響應語言變化
final currentLang = context.watch<UserStateProvider>().currentLanguage;
```

**2. `_buildKeyWordsAnalysisInline()` 方法**
```dart
// 使用 context.watch 實時監聽語言變化
final currentLang = context.watch<UserStateProvider>().currentLanguage;
final keyWords = widget.question.getKeyWords(currentLang);
```

**3. 關鍵詞顯示**
```dart
// 降級邏輯已在 getKeyWords 中處理，直接使用對應語言的翻譯
TextSpan(
  text: ' ${keyWords[i][currentLang] ?? ''}',
  // ...
)
```

---

### 4. 降級顯示邏輯

#### 實現位置
- **Question 模型**: `getKeyWords()` 方法中實現降級邏輯
- **QuestionWidget**: 直接使用降級後的結果

#### 降級流程
```
用戶選擇語言 → getKeyWords(languageCode)
  ↓
檢查是否包含目標語言
  ↓
是 → 返回目標語言翻譯
  ↓
否 → 檢查英語
  ↓
是 → 返回英語翻譯
  ↓
否 → 檢查中文
  ↓
是 → 返回中文翻譯
  ↓
否 → 返回意大利語（原始語言）
```

#### 示例
```dart
// 假設關鍵詞數據：{"it": "carreggiata", "zh": "车行道", "en": "carriageway"}
// 用戶選擇俄語（ru），但數據中沒有俄語翻譯

// getKeyWords('ru') 會返回：
[
  {
    "it": "carreggiata",
    "ru": "carriageway"  // 降級到英語
  }
]
```

---

## 🔄 實時響應機制

### 語言切換流程

1. **用戶切換語言**
   ```
   設置頁面 → 選擇新語言 → UserStateProvider.changeLanguage()
   ```

2. **Provider 通知更新**
   ```
   UserStateProvider.notifyListeners()
   ```

3. **Widget 自動重建**
   ```
   context.watch<UserStateProvider>() 檢測到變化
   → build() 方法重新執行
   → _buildKeyWordsAnalysisInline() 重新執行
   → 使用新語言獲取關鍵詞
   → UI 自動更新
   ```

4. **關鍵詞顯示更新**
   ```
   getKeyWords(newLanguage)
   → 返回新語言的翻譯（或降級後的翻譯）
   → UI 顯示更新後的關鍵詞
   ```

---

## 📋 代碼變更摘要

### 文件 1: `lib/models/question.dart`

**主要變更**:
- 優化 `getKeyWords()` 方法的扁平格式處理邏輯
- 實現智能降級：目標語言 → 英語 → 中文 → 意大利語
- 確保返回的關鍵詞包含意大利語和對應語言的翻譯

**關鍵代碼**:
```dart
// 語言降級邏輯
String? translation;
if (keywordMap.containsKey(languageCode) && keywordMap[languageCode]!.isNotEmpty) {
  translation = keywordMap[languageCode];
} else if (keywordMap.containsKey('en') && keywordMap['en']!.isNotEmpty) {
  translation = keywordMap['en'];  // 降級到英語
} else if (keywordMap.containsKey('zh') && keywordMap['zh']!.isNotEmpty) {
  translation = keywordMap['zh'];  // 降級到中文
} else {
  translation = keywordMap['it'];  // 最後降級到意大利語
}
```

### 文件 2: `lib/widgets/question_widget.dart`

**主要變更**:
- `build()` 方法：使用 `context.watch` 實時監聽語言變化
- `_buildKeyWordsAnalysisInline()` 方法：使用 `context.watch` 獲取當前語言
- 簡化關鍵詞顯示邏輯（降級已在模型層處理）

**關鍵代碼**:
```dart
// build() 方法
final currentLang = context.watch<UserStateProvider>().currentLanguage;

// _buildKeyWordsAnalysisInline() 方法
final currentLang = context.watch<UserStateProvider>().currentLanguage;
final keyWords = widget.question.getKeyWords(currentLang);

// 關鍵詞顯示
TextSpan(
  text: ' ${keyWords[i][currentLang] ?? ''}',
  // 降級邏輯已在 getKeyWords 中處理
)
```

---

## 🎯 使用示例

### 場景 1: 完整翻譯
```dart
// 數據：{"it": "carreggiata", "zh": "车行道", "en": "carriageway", "ru": "проезжая часть"}
// 用戶選擇俄語（ru）

final keyWords = question.getKeyWords('ru');
// 返回：[{"it": "carreggiata", "ru": "проезжая часть"}]
// UI 顯示：carreggiata проезжая часть
```

### 場景 2: 降級到英語
```dart
// 數據：{"it": "carreggiata", "zh": "车行道", "en": "carriageway"}
// 用戶選擇俄語（ru），但數據中沒有俄語翻譯

final keyWords = question.getKeyWords('ru');
// 返回：[{"it": "carreggiata", "ru": "carriageway"}]  // 降級到英語
// UI 顯示：carreggiata carriageway
```

### 場景 3: 降級到中文
```dart
// 數據：{"it": "carreggiata", "zh": "车行道"}
// 用戶選擇俄語（ru），但數據中沒有俄語和英語翻譯

final keyWords = question.getKeyWords('ru');
// 返回：[{"it": "carreggiata", "ru": "车行道"}]  // 降級到中文
// UI 顯示：carreggiata 车行道
```

---

## ✅ 測試建議

### 1. 語言切換測試
- 在設置頁面切換到不同語言（中文、英文、俄語、烏克蘭語等）
- 確認關鍵詞顯示立即更新為對應語言的翻譯
- 驗證 UI 響應速度（應該立即更新，無延遲）

### 2. 降級邏輯測試
- 選擇一個沒有完整翻譯的題目
- 切換到缺少翻譯的語言（如俄語，但數據中只有中文和英文）
- 確認降級邏輯正確工作（應該顯示英語或中文）

### 3. 實時響應測試
- 在題目顯示頁面，不關閉頁面，直接切換語言
- 確認關鍵詞顯示立即更新
- 驗證不需要重新加載題目

---

## 📝 注意事項

### 1. 性能考慮
- `context.watch` 會導致 Widget 在語言變化時重建
- 但由於只重建必要的部分，性能影響很小
- 關鍵詞解析結果會被緩存在 Question 對象中

### 2. 降級邏輯
- 降級邏輯在模型層（Question）實現
- UI 層（QuestionWidget）不需要處理降級
- 確保邏輯集中，易於維護

### 3. 語言代碼一致性
- 確保 App 內部語言代碼與數據庫 JSON 鍵名一致
- 如果添加新語言，需要同時更新：
  - `UserState.supportedLanguages`
  - `UserState.languageNames`
  - 數據庫中的關鍵詞數據

---

## 🔄 後續優化建議

### 1. 緩存優化
- 可以考慮在 Question 對象中緩存已解析的關鍵詞
- 避免重複解析相同語言的關鍵詞

### 2. 降級策略配置
- 可以將降級策略配置化
- 允許用戶自定義降級順序

### 3. 翻譯質量標記
- 可以標記翻譯來源（原始語言 vs 降級語言）
- 在 UI 中顯示翻譯來源提示

---

## ✅ 完成狀態

- [x] Question 模型優化（支持從扁平格式提取對應語言）
- [x] 語言代碼映射確認（App 內部代碼與 JSON 鍵名一致）
- [x] QuestionWidget 使用 context.watch 實時監聽
- [x] 實現降級邏輯（目標語言 → 英語 → 中文 → 意大利語）
- [x] 關鍵詞顯示實時刷新
- [x] 代碼檢查通過（無 Linter 錯誤）

---

*重構完成時間: 2024年12月*
*下次更新: 根據實際使用反饋進行優化*
