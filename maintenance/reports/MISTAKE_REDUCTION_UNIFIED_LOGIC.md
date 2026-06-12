# 全模式統一錯題消減邏輯與 UI 自動刷新完成報告

**完成時間**: 2024年12月
**目標**: 統一錯題消減邏輯，實現 UI 自動刷新和交互反饋

---

## ✅ 已完成的修改

### 1. 修改 `DatabaseService.updateQuestionProgress`

#### 統一邏輯實現
- **位置**: `lib/services/database_service.dart` 第 1508-1566 行
- **變更**: 答對時，如果 `wrong_count > 0`，自動減少 1

#### 關鍵代碼
```dart
if (isCorrect) {
  // 查詢當前的 wrong_count
  final currentWrongCount = result.isEmpty ? 0 : (result.first['wrong_count'] as int? ?? 0);

  // 計算新的 wrong_count（如果 > 0，減少 1）
  final newWrongCount = currentWrongCount > 0 ? currentWrongCount - 1 : 0;

  // 更新數據庫
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

#### 邏輯說明
- ✅ **答對時**: `correct_streak + 1`，如果達到 3 次則 `is_mastered = 1`，**同時 `wrong_count - 1`**（如果 > 0）
- ✅ **答錯時**: `correct_streak = 0`，`is_mastered = 0`，`wrong_count + 1`
- ✅ **保持原有邏輯**: 3 連對邏輯不變，掌握度聯動正常

---

### 2. 優化 `UserStateProvider` 狀態通知

#### 新增錯題數量統計
- **位置**: `lib/providers/user_state_provider.dart`
- **新增字段**: `_mistakeCount` - 錯題數量（`wrong_count > 0` 的題目數）
- **新增 Getter**: `mistakeCount` - 獲取錯題數量

#### 新增刷新方法
```dart
/// 刷新錯題數量統計（從數據庫查詢 wrong_count > 0 的題目數）
Future<void> refreshMistakeCount() async {
  try {
    final wrongQuestions = await DatabaseService.getWrongQuestions(
      effectiveUserId,
      lang: 'it',
    );
    _mistakeCount = wrongQuestions.length;
    notifyListeners();  // 通知所有監聽者
  } catch (e) {
    print('⚠️ [UserStateProvider] 刷新錯題數量統計失敗: $e');
  }
}
```

#### 更新 `updateQuestionProgress` 方法
```dart
Future<bool> updateQuestionProgress(String questionId, bool isCorrect) async {
  final newlyMastered = await DatabaseService.updateQuestionProgress(
    questionId,
    isCorrect,
    userId: effectiveUserId,
  );
  await incrementDailyQuizCount();
  // 🔄 更新錯題數量統計並通知監聽者
  await refreshMistakeCount();
  return newlyMastered;
}
```

#### 初始化時加載
- 在 `_loadUserState()` 中調用 `refreshMistakeCount()`
- 確保應用啟動時錯題數量已加載

---

### 3. 修復 `MistakeReviewScreen` 實時刷新

#### 修改 `_openReview` 方法
- **位置**: `lib/screens/mistake_review_screen.dart` 第 95-119 行
- **變更**: 從答題頁返回時，強制重新加載錯題列表

```dart
Future<void> _openReview(WrongQuestionEntry entry, int index) async {
  await Navigator.push<int>(...);

  // 🔄 無論返回什麼結果，都重新加載錯題列表以確保數據同步
  if (mounted) {
    await _loadErrorQuestions();
  }
}
```

#### 修改錯題複習答題邏輯
- **位置**: `lib/screens/mistake_review_screen.dart` 第 326-356 行
- **變更**: 使用統一的 `updateQuestionProgress` 方法

```dart
Future<void> _onAnswerSelected(bool selectedAnswer) async {
  final isCorrect = selectedAnswer == question.answer;

  // 🔄 使用統一的 updateQuestionProgress 方法（會自動減少 wrong_count）
  final userStateProvider = Provider.of<UserStateProvider>(context, listen: false);
  await userStateProvider.updateQuestionProgress(question.id, isCorrect);

  // 獲取更新後的 wrong_count
  final wrongQuestions = await DatabaseService.getWrongQuestions(...);
  final newCount = updatedEntry.wrongCount;

  // 根據結果顯示反饋
  ...
}
```

---

### 4. 增加交互反饋

#### 震動反饋
- **導入**: `import 'package:flutter/services.dart';`
- **實現**: 當 `wrong_count` 減到 0 時，觸發 `HapticFeedback.mediumImpact()`

#### 視覺反饋
- **成功提示**: 顯示帶圖標的綠色 SnackBar
- **內容**: "錯題已消滅！" + 勾選圖標
- **持續時間**: 2 秒

#### 代碼實現
```dart
if (isCorrect) {
  // 如果 wrong_count 減到 0，顯示特殊反饋
  if (newCount == 0) {
    // 輕微震動反饋
    HapticFeedback.mediumImpact();

    // 顯示成功提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            const Text('錯題已消滅！'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('答對了，錯誤次數已減少（剩餘 $newCount 次）'),
      ),
    );
  }
}
```

---

## 🔄 完整流程

### 普通練習模式

```
用戶答題
  ↓
updateQuestionProgress(questionId, isCorrect)
  ↓
如果 isCorrect = true:
  - correct_streak + 1
  - 如果 wrong_count > 0，wrong_count - 1
  - 如果 correct_streak >= 3，is_mastered = 1
  ↓
UserStateProvider.refreshMistakeCount()
  ↓
notifyListeners()
  ↓
UI 自動更新（錯題數量、錯題列表等）
```

### 錯題複習模式

```
用戶進入錯題複習頁面
  ↓
點擊一道錯題
  ↓
進入答題頁面
  ↓
用戶答題
  ↓
updateQuestionProgress(questionId, isCorrect)
  ↓
如果 isCorrect = true:
  - wrong_count - 1
  - 如果 wrong_count = 0，顯示"錯題已消滅！" + 震動
  ↓
返回錯題列表頁面
  ↓
自動重新加載錯題列表
  ↓
已消滅的錯題立即消失
```

---

## 📊 數據字段更新邏輯

### 答對時（`isCorrect = true`）

| 字段 | 更新邏輯 |
|------|----------|
| `correct_streak` | +1 |
| `is_mastered` | 如果 `correct_streak >= 3`，設為 1 |
| `wrong_count` | **如果 > 0，減少 1**（新增） |
| `total_attempts` | +1 |

### 答錯時（`isCorrect = false`）

| 字段 | 更新邏輯 |
|------|----------|
| `correct_streak` | 重置為 0 |
| `is_mastered` | 設為 0 |
| `wrong_count` | +1 |
| `total_attempts` | +1 |

---

## 🎯 關鍵改進

### 1. 邏輯統一
- ✅ **之前**: 普通練習模式答對不會減少 `wrong_count`，錯題複習模式答對會減少
- ✅ **現在**: 所有模式統一，答對時自動減少 `wrong_count`

### 2. 狀態同步
- ✅ **之前**: 錯題數量更新後，UI 不會自動刷新
- ✅ **現在**: 通過 `refreshMistakeCount()` 和 `notifyListeners()` 實現實時更新

### 3. UI 刷新
- ✅ **之前**: 錯題列表需要手動刷新才能看到變化
- ✅ **現在**: 從答題頁返回時自動重新加載，已消滅的錯題立即消失

### 4. 用戶體驗
- ✅ **之前**: 沒有明確的反饋提示
- ✅ **現在**: 錯題消滅時有震動和視覺反饋，增強成就感

---

## 📋 使用示例

### 場景 1: 普通練習模式答對錯題

```
用戶在普通練習模式下遇到一道錯題（wrong_count = 2）
  ↓
用戶答對
  ↓
updateQuestionProgress(questionId, true)
  ↓
wrong_count: 2 → 1（自動減少）
correct_streak: 0 → 1
  ↓
UserStateProvider.refreshMistakeCount()
  ↓
首頁錯題數量自動更新
```

### 場景 2: 錯題複習模式消滅錯題

```
用戶進入錯題複習頁面
  ↓
點擊一道錯題（wrong_count = 1）
  ↓
進入答題頁面
  ↓
用戶答對
  ↓
updateQuestionProgress(questionId, true)
  ↓
wrong_count: 1 → 0（已消滅）
  ↓
顯示"錯題已消滅！" + 震動反饋
  ↓
返回錯題列表
  ↓
自動重新加載，該題目已從列表中消失
```

---

## ✅ 完成狀態

- [x] 修改 `updateQuestionProgress`，答對時自動減少 `wrong_count`
- [x] 優化 `UserStateProvider`，新增錯題數量統計和刷新方法
- [x] 修復 `MistakeReviewScreen`，返回時自動重新加載
- [x] 增加交互反饋（震動 + 視覺提示）
- [x] 統一所有模式的錯題消減邏輯
- [x] 確保狀態通知機制正常工作
- [x] 代碼檢查通過（無 Linter 錯誤）

---

## 🔍 測試建議

### 1. 普通練習模式測試
- 在普通練習模式下答對一道錯題
- 確認錯題數量自動減少
- 確認首頁錯題數量實時更新

### 2. 錯題複習模式測試
- 進入錯題複習頁面
- 答對一道錯題（wrong_count = 1）
- 確認顯示"錯題已消滅！"提示和震動
- 確認返回列表頁時，該題目已消失

### 3. 狀態同步測試
- 在錯題複習模式下答對一道題
- 返回首頁，確認錯題數量已更新
- 再次進入錯題複習頁面，確認列表已更新

---

## 📝 注意事項

### 1. 性能考慮
- `refreshMistakeCount()` 會查詢數據庫，但由於錯題數量通常不多，性能影響很小
- 可以考慮緩存錯題列表，但需要確保數據一致性

### 2. 狀態一致性
- 確保所有更新錯題數量的地方都調用 `refreshMistakeCount()`
- 確保 `notifyListeners()` 在數據更新後立即調用

### 3. 用戶體驗
- 震動反饋只在錯題完全消滅時觸發，避免過度反饋
- 視覺提示清晰明確，讓用戶知道錯題已消滅

---

*完成時間: 2024年12月*
*下次更新: 根據實際使用反饋進行優化*
