# 錯題複習邏輯分析報告

**分析時間**: 2024年12月
**相關文件**:
- `lib/services/database_service.dart`
- `lib/screens/mistake_review_screen.dart`

---

## 📋 問題回答

### 1. `updateQuestionProgress` 方法如何處理答對和答錯？

#### 方法位置
- **文件**: `lib/services/database_service.dart`
- **行數**: 1508-1566

#### 答對（`isCorrect = true`）的處理邏輯

```dart
if (isCorrect) {
  // correct_streak + 1
  final newStreak = currentStreak + 1;

  // 如果達到 3 次，設置 is_mastered = 1
  final shouldMaster = newStreak >= 3;

  // 更新數據庫
  // - correct_streak = newStreak
  // - is_mastered = shouldMaster ? 1 : 0
  // - total_attempts + 1
  // ⚠️ 注意：不會減少 wrong_count
}
```

**關鍵點**:
- ✅ `correct_streak` 增加 1
- ✅ 如果 `correct_streak >= 3`，設置 `is_mastered = 1`
- ✅ `total_attempts` 增加 1
- ❌ **不會減少 `wrong_count`**

#### 答錯（`isCorrect = false`）的處理邏輯

```dart
else {
  // 答錯了：
  // - correct_streak = 0（重置連對次數）
  // - is_mastered = 0（取消已掌握標記）
  // - wrong_count + 1（增加錯誤計數）
  // - total_attempts + 1
}
```

**關鍵點**:
- ✅ `correct_streak` 重置為 0
- ✅ `is_mastered` 設置為 0
- ✅ `wrong_count` 增加 1
- ✅ `total_attempts` 增加 1

---

### 2. `mistake_review_screen.dart` 如何獲取錯題列表？

#### 方法調用
- **文件**: `lib/screens/mistake_review_screen.dart`
- **行數**: 43-46

```dart
final questions = await DatabaseService.getWrongQuestions(
  userStateProvider.effectiveUserId,
  lang: 'it',
);
```

#### SQL 查詢語句

**位置**: `lib/services/database_service.dart` 第 1867-1872 行

```sql
SELECT question_id, wrong_count
FROM user_progress
WHERE user_id = ? AND wrong_count > 0
ORDER BY wrong_count DESC, last_practiced DESC
```

**篩選條件**:
- ✅ **根據 `wrong_count > 0` 篩選**
- ❌ **不是根據 `is_mastered = 0` 篩選**

**排序**:
- 優先顯示錯誤次數最多的題目（`wrong_count DESC`）
- 其次按最後練習時間排序（`last_practiced DESC`）

---

### 3. 答對後是否會減少 `wrong_count`？何時從錯題列表消失？

#### 錯題複習模式下的處理

**位置**: `lib/screens/mistake_review_screen.dart` 第 326-356 行

```dart
Future<void> _onAnswerSelected(bool selectedAnswer) async {
  final isCorrect = selectedAnswer == question.answer;

  if (isCorrect) {
    // 答對了：調用 decreaseErrorCount
    final newCount = await DatabaseService.decreaseErrorCount(
      question.id,
      userId: widget.userId,
    );
    Navigator.pop(context, newCount);
  } else {
    // 答錯了：調用 recordError
    await DatabaseService.recordError(
      question.id,
      userId: widget.userId,
    );
    Navigator.pop(context, widget.entry.wrongCount + 1);
  }
}
```

#### `decreaseErrorCount` 方法實現

**位置**: `lib/services/database_service.dart` 第 1935-1965 行

```dart
static Future<int> decreaseErrorCount(String questionId, {required String userId}) async {
  // 獲取當前錯誤計數
  final currentError = result.first['error_count'] as int;
  final currentWrong = result.first['wrong_count'] as int? ?? 0;

  if (currentError > 0 || currentWrong > 0) {
    // 減少錯誤計數（每次減少 1）
    await db.update(
      'user_progress',
      {
        'error_count': currentError > 0 ? currentError - 1 : 0,
        'wrong_count': currentWrong > 0 ? currentWrong - 1 : 0,
      },
      ...
    );

    // 返回新的 wrong_count
    return currentWrong > 0 ? currentWrong - 1 : 0;
  }

  return 0;
}
```

#### 答案總結

**問題 1**: 答對後是否會減少 `wrong_count`？
- ✅ **是的**，在錯題複習模式下，答對會調用 `decreaseErrorCount`，將 `wrong_count` 減少 1

**問題 2**: 必須達到 3 連對（`is_mastered = 1`）才會從錯題列表消失嗎？
- ❌ **不是**，題目從錯題列表消失的條件是：`wrong_count = 0`
- 只要 `wrong_count > 0`，題目就會出現在錯題列表中
- `is_mastered` 狀態不影響錯題列表的顯示

---

## 🔄 完整流程圖

### 錯題複習流程

```
用戶進入錯題複習頁面
  ↓
調用 getWrongQuestions()
  ↓
SQL: WHERE wrong_count > 0
  ↓
顯示錯題列表
  ↓
用戶點擊一道錯題
  ↓
進入練習頁面
  ↓
用戶答題
  ↓
┌─────────────────┬─────────────────┐
│   答對了         │   答錯了         │
│                 │                 │
│ decreaseErrorCount() │ recordError() │
│                 │                 │
│ wrong_count - 1 │ wrong_count + 1 │
│                 │                 │
│ 返回新計數      │ 返回新計數      │
└─────────────────┴─────────────────┘
  ↓
更新錯題列表
  ↓
如果 wrong_count = 0，題目從列表中移除
```

---

## 📊 數據字段說明

### `user_progress` 表字段

| 字段 | 說明 | 更新邏輯 |
|------|------|----------|
| `wrong_count` | 錯誤次數 | 答錯時 +1，錯題複習答對時 -1 |
| `error_count` | 錯誤計數（舊字段） | 答錯時 +1，錯題複習答對時 -1 |
| `correct_streak` | 連續答對次數 | 答對時 +1，答錯時重置為 0 |
| `is_mastered` | 是否已掌握 | `correct_streak >= 3` 時設為 1，答錯時設為 0 |
| `total_attempts` | 總嘗試次數 | 每次答題 +1 |

---

## 🎯 關鍵發現

### 1. 兩種不同的答對處理邏輯

#### 普通練習模式
- 使用 `updateQuestionProgress()` 或 `recordCorrectAnswer()`
- **不會減少 `wrong_count`**
- 只會增加 `correct_streak`
- 達到 3 連對時設置 `is_mastered = 1`

#### 錯題複習模式
- 使用 `decreaseErrorCount()`
- **會減少 `wrong_count`**
- 每次答對減少 1
- 當 `wrong_count = 0` 時，題目從錯題列表消失

### 2. 錯題列表篩選邏輯

- **篩選條件**: `wrong_count > 0`
- **不依賴**: `is_mastered` 狀態
- **排序**: 按 `wrong_count DESC`（錯誤次數多的在前）

### 3. 題目從錯題列表消失的條件

- **條件**: `wrong_count = 0`
- **方式**: 在錯題複習模式下，每次答對減少 1
- **不依賴**: `is_mastered` 狀態（即使 `is_mastered = 1`，如果 `wrong_count > 0`，仍會出現在錯題列表中）

---

## ⚠️ 潛在問題

### 問題 1: 邏輯不一致

**現象**:
- 普通練習模式下答對，不會減少 `wrong_count`
- 錯題複習模式下答對，會減少 `wrong_count`

**影響**:
- 如果用戶在普通練習模式下答對一道錯題，該題目仍會留在錯題列表中
- 只有在錯題複習模式下答對，才會減少 `wrong_count`

### 問題 2: `is_mastered` 與錯題列表的關係

**現象**:
- `is_mastered = 1` 表示已掌握（3 連對）
- 但錯題列表只根據 `wrong_count > 0` 篩選

**影響**:
- 一道題可能同時滿足 `is_mastered = 1` 和 `wrong_count > 0`
- 這意味著題目已掌握，但仍會出現在錯題列表中

---

## 💡 建議改進

### 建議 1: 統一答對處理邏輯

**方案**: 在 `updateQuestionProgress` 中，當答對時也減少 `wrong_count`

```dart
if (isCorrect) {
  // 如果 wrong_count > 0，減少 1
  // 這樣無論在哪種模式下答對，都會減少錯誤計數
  await txn.rawInsert('''
    ...
    wrong_count = CASE
      WHEN wrong_count > 0 THEN wrong_count - 1
      ELSE 0
    END,
    ...
  ''');
}
```

### 建議 2: 優化錯題列表篩選

**方案**: 同時考慮 `wrong_count` 和 `is_mastered`

```sql
SELECT question_id, wrong_count
FROM user_progress
WHERE user_id = ?
  AND wrong_count > 0
  AND is_mastered = 0  -- 已掌握的題目不再顯示
ORDER BY wrong_count DESC, last_practiced DESC
```

---

## ✅ 總結

### 問題 1 答案
- **答對**: `correct_streak + 1`，達到 3 次時 `is_mastered = 1`，**不會減少 `wrong_count`**
- **答錯**: `correct_streak = 0`，`is_mastered = 0`，`wrong_count + 1`

### 問題 2 答案
- **SQL 查詢**: `WHERE user_id = ? AND wrong_count > 0`
- **篩選依據**: `wrong_count > 0`，**不是** `is_mastered = 0`

### 問題 3 答案
- **答對後**: 在錯題複習模式下，會調用 `decreaseErrorCount` 減少 `wrong_count`
- **消失條件**: 當 `wrong_count = 0` 時，題目從錯題列表消失
- **不依賴**: 不需要達到 3 連對（`is_mastered = 1`），只要 `wrong_count = 0` 即可

---

*分析完成時間: 2024年12月*
