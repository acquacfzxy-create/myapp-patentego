# 多語言關鍵詞支持優化完成報告

**更新時間**: 2024年12月
**操作**: 優化 Question 模型和 QuestionWidget 以支持多語言關鍵詞

---

## ✅ 已完成的優化

### 1. Question 模型優化

#### 新增方法：`getKeyWords(String languageCode)`
- **位置**: `lib/models/question.dart`
- **功能**: 支持多語言關鍵詞解析
- **參數**: `languageCode` - 目標語言代碼（如 'zh', 'en', 'ru', 'it'）

#### 支持的數據格式

**格式 1：舊格式（扁平）**
```json
[
  {"it": "carreggiata", "zh": "车行道"},
  {"it": "sorpassare", "zh": "超车"}
]
```
- 直接返回包含目標語言翻譯的關鍵詞列表
- 如果目標語言不存在，使用意大利語和中文（向後兼容）

**格式 2：新格式（多語言嵌套）**
```json
{
  "it": [{"it": "carreggiata", "zh": "车行道"}, ...],
  "zh": [{"it": "carreggiata", "zh": "车行道"}, ...],
  "en": [{"it": "carreggiata", "en": "carriageway"}, ...]
}
```
- 根據語言代碼返回對應語言的關鍵詞列表
- 如果目標語言不存在，按優先級使用：
  1. 意大利語（'it'）
  2. 英語（'en'）
  3. 第一個可用的語言

#### 向後兼容
- 保留了 `keyWords` getter（標記為 `@Deprecated`）
- 默認使用 'zh' 語言，確保舊代碼仍可工作

---

### 2. QuestionWidget 優化

#### 從 UserStateProvider 獲取當前語言
- **位置**: `lib/widgets/question_widget.dart`
- **方法**: `_buildKeyWordsAnalysisInline()`
- **變更**:
  - 從 `UserStateProvider` 獲取 `currentLanguage`
  - 將語言代碼傳遞給 `question.getKeyWords(currentLang)`

#### 更新所有關鍵詞使用處
1. **`_buildKeyWordsAnalysisInline()` 方法**
   - 使用 `getKeyWords(currentLang)` 獲取當前語言的關鍵詞
   - 顯示時使用當前語言的翻譯（而非固定使用 'zh'）

2. **`build()` 方法**
   - 更新調試日誌，使用 `getKeyWords(currentLang)`
   - 移除對已棄用的 `keyWords` getter 的直接調用

3. **翻譯按鈕點擊處理**
   - 更新調試日誌，使用 `getKeyWords(currentLang)`

4. **關鍵詞顯示條件檢查**
   - 使用 `Builder` widget 獲取當前語言
   - 動態檢查關鍵詞是否為空

---

## 🔧 技術實現細節

### 語言優先級邏輯

當目標語言不存在時，按以下順序嘗試：
1. **目標語言**（如 'zh', 'en', 'ru'）
2. **意大利語**（'it'）- 原始語言
3. **英語**（'en'）- 通用語言
4. **第一個可用語言** - 兜底方案

### 關鍵詞顯示邏輯

在 `_buildKeyWordsAnalysisInline()` 中：
- 意大利語單詞：深藍色加粗顯示
- 當前語言翻譯：灰色小字顯示
- 如果當前語言翻譯不存在，嘗試使用中文或英語

---

## 📋 代碼變更摘要

### 文件 1: `lib/models/question.dart`

**新增導入**:
```dart
import 'package:flutter/foundation.dart' show kDebugMode;
```

**新增方法**:
```dart
List<Map<String, String>> getKeyWords(String languageCode)
```

**向後兼容**:
```dart
@Deprecated('請使用 getKeyWords(String languageCode) 方法以支持多語言')
List<Map<String, String>> get keyWords
```

### 文件 2: `lib/widgets/question_widget.dart`

**新增導入**:
```dart
import 'package:flutter/foundation.dart' show kDebugMode;
```

**主要變更**:
- `_buildKeyWordsAnalysisInline()`: 從 Provider 獲取語言並傳遞給 `getKeyWords()`
- `build()`: 更新調試日誌，使用 `getKeyWords()`
- 關鍵詞顯示：使用當前語言的翻譯而非固定 'zh'

---

## 🎯 使用示例

### 獲取當前語言的關鍵詞

```dart
// 在 QuestionWidget 中
final userStateProvider = Provider.of<UserStateProvider>(context, listen: false);
final currentLang = userStateProvider.currentLanguage;
final keyWords = question.getKeyWords(currentLang);
```

### 顯示關鍵詞

```dart
// 意大利語單詞
TextSpan(
  text: keyWords[i]['it'] ?? '',
  style: TextStyle(
    fontWeight: FontWeight.bold,
    color: Colors.blue[800],
  ),
)

// 當前語言翻譯
TextSpan(
  text: ' ${keyWords[i][currentLang] ?? keyWords[i]['zh'] ?? keyWords[i]['en'] ?? ''}',
  style: TextStyle(
    fontSize: 13,
    color: Colors.grey[600],
  ),
)
```

---

## ✅ 測試建議

### 1. 語言切換測試
- 切換到不同語言（中文、英語、俄語等）
- 確認關鍵詞顯示為對應語言的翻譯
- 如果某語言沒有翻譯，確認使用備用語言

### 2. 數據格式兼容性測試
- 測試舊格式（扁平）的關鍵詞數據
- 測試新格式（多語言嵌套）的關鍵詞數據
- 確認兩種格式都能正確解析

### 3. 邊界情況測試
- 測試沒有關鍵詞的題目（應不顯示）
- 測試只有意大利語的關鍵詞（應顯示意大利語）
- 測試目標語言不存在的情況（應使用備用語言）

---

## 📝 注意事項

1. **向後兼容**:
   - 舊代碼仍可使用 `keyWords` getter（默認使用 'zh'）
   - 建議逐步遷移到 `getKeyWords(languageCode)` 方法

2. **性能考慮**:
   - `getKeyWords()` 方法會解析 JSON，但結果會被緩存在 Question 對象中
   - 建議在需要時才調用，避免重複解析

3. **調試模式**:
   - 所有調試日誌都使用 `kDebugMode` 檢查
   - Release 模式下不會輸出調試信息

---

## 🔄 後續優化建議

1. **緩存優化**:
   - 可以考慮在 Question 對象中緩存已解析的關鍵詞
   - 避免重複解析相同語言的關鍵詞

2. **數據格式統一**:
   - 建議統一使用新格式（多語言嵌套）
   - 逐步遷移舊格式數據

3. **語言支持擴展**:
   - 根據實際需求添加更多語言支持
   - 確保數據庫中有對應語言的翻譯數據

---

## ✅ 完成狀態

- [x] Question 模型支持多語言關鍵詞
- [x] QuestionWidget 從 Provider 獲取當前語言
- [x] 更新所有關鍵詞使用處
- [x] 向後兼容舊代碼
- [x] 添加調試日誌
- [x] 代碼檢查通過（無 Linter 錯誤）

---

*更新完成時間: 2024年12月*
*下次更新: 根據實際使用反饋進行優化*
