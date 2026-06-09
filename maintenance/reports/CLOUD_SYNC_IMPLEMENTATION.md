# 數據雲端同步功能實現報告

**實現時間**: 2024年12月
**功能**: Firestore 雲端同步用戶學習進度

---

## ✅ 已完成的實現

### 1. 添加 Firestore 依賴

- **文件**: `pubspec.yaml`
- **變更**: 添加 `cloud_firestore: ^6.1.1`
- **狀態**: ✅ 已安裝

---

### 2. Firestore 數據結構

#### 集合路徑
```
users/{userId}/progress/{questionId}
```

#### 文檔結構
```json
{
  "question_id": "550-0",
  "is_favorite": 0,
  "error_count": 2,
  "wrong_count": 2,
  "is_mastered": 0,
  "correct_streak": 0,
  "total_attempts": 5,
  "last_practiced": 1704067200,
  "synced_at": "2024-12-30T12:00:00Z"
}
```

#### 字段說明
- `question_id`: 題目ID（文檔ID）
- `is_favorite`: 是否收藏（0/1）
- `error_count`: 錯誤次數
- `wrong_count`: 錯題次數
- `is_mastered`: 是否已掌握（0/1）
- `correct_streak`: 連續答對次數
- `total_attempts`: 總嘗試次數
- `last_practiced`: 最後練習時間（Unix 時間戳）
- `synced_at`: 同步時間（服務器時間戳）

---

### 3. DatabaseService 雲端同步方法

#### `syncProgressToCloud()`

**位置**: `lib/services/database_service.dart` 第 2239-2305 行

**功能**:
- 將本地 `user_progress` 表中所有有變動的記錄（`total_attempts > 0`）上傳到 Firestore
- 使用批量寫入（Batch）提高效率
- 添加 `synced_at` 時間戳標記同步時間

**邏輯**:
```dart
// 1. 檢查用戶是否已登入
if (currentUser == null || currentUser.uid != userId) {
  throw Exception('用戶未登入，無法同步到雲端');
}

// 2. 查詢所有有變動的記錄
SELECT * FROM user_progress
WHERE user_id = ? AND total_attempts > 0

// 3. 批量寫入 Firestore
batch.set(progressRef, progressData, SetOptions(merge: true));

// 4. 提交批量操作
await batch.commit();
```

**返回**: `bool` - 是否全部成功

---

#### `restoreProgressFromCloud()`

**位置**: `lib/services/database_service.dart` 第 2307-2427 行

**功能**:
- 從 Firestore 下載用戶進度數據
- 合併到本地 SQLite 數據庫
- 保留本地較新的數據（基於 `last_practiced` 時間戳）

**邏輯**:
```dart
// 1. 從 Firestore 獲取所有進度記錄
users/{userId}/progress

// 2. 對每條記錄：
//    - 如果本地沒有：直接插入
//    - 如果本地有：比較 last_practiced，保留較新的

if (cloudLastPracticed > localLastPracticed) {
  // 使用雲端數據
} else {
  // 保留本地數據
}
```

**返回**: `bool` - 是否成功

---

### 4. UserStateProvider 集成

#### 新增方法

**`syncProgressToCloud()`**
- **位置**: `lib/providers/user_state_provider.dart` 第 697-712 行
- **功能**: 調用 `DatabaseService.syncProgressToCloud()`
- **限制**: 僅 VIP 用戶可以使用

**`_restoreProgressFromCloud()`**
- **位置**: `lib/providers/user_state_provider.dart` 第 683-696 行
- **功能**: 自動從雲端恢復用戶進度
- **觸發**: 登入成功後（僅 VIP 用戶）

#### 登入後自動恢復

**位置**: `lib/providers/user_state_provider.dart` 第 108-113 行

```dart
if (user != null) {
  _syncVipFromFirebase(user);
  // 🔄 自動從雲端恢復用戶進度（僅 VIP 用戶）
  if (_isVip) {
    _restoreProgressFromCloud();
  }
}
```

---

### 5. SettingsScreen UI 實現

#### VIP 用戶同步按鈕

**位置**: `lib/screens/settings_screen.dart` 第 170-180 行

```dart
if (isLoggedIn && isVip) ...[
  const Divider(),
  ListTile(
    leading: const Icon(Icons.cloud_upload, color: Colors.blue),
    title: const Text('立即同步'),
    subtitle: const Text('將學習進度同步到雲端'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => _handleSyncToCloud(context, userStateProvider),
  ),
],
```

#### 非 VIP 用戶提示

**位置**: `lib/screens/settings_screen.dart` 第 182-195 行

```dart
if (isLoggedIn && !isVip) ...[
  const Divider(),
  ListTile(
    leading: const Icon(Icons.cloud_upload, color: Colors.grey),
    title: const Text('雲端同步'),
    subtitle: const Text('升級為 VIP 會員以使用雲端同步功能'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const PremiumScreen(),
        ),
      );
    },
  ),
],
```

#### 同步處理方法

**位置**: `lib/screens/settings_screen.dart` 第 348-410 行

**功能**:
- 檢查 VIP 狀態和登入狀態
- 顯示加載指示器
- 執行同步操作
- 顯示結果提示（成功/失敗）

---

## 🔄 完整流程

### 場景 1: VIP 用戶手動同步

```
用戶進入設置頁面
  ↓
點擊"立即同步"按鈕
  ↓
檢查 VIP 狀態和登入狀態
  ↓
顯示加載指示器
  ↓
調用 UserStateProvider.syncProgressToCloud()
  ↓
DatabaseService.syncProgressToCloud()
  ↓
查詢本地有變動的記錄（total_attempts > 0）
  ↓
批量寫入 Firestore
  ↓
顯示成功/失敗提示
```

### 場景 2: VIP 用戶登入後自動恢復

```
用戶登入成功
  ↓
UserStateProvider._initAuthListener() 檢測到登入
  ↓
檢查是否為 VIP 用戶
  ↓
調用 _restoreProgressFromCloud()
  ↓
DatabaseService.restoreProgressFromCloud()
  ↓
從 Firestore 下載所有進度記錄
  ↓
合併到本地 SQLite（保留較新的數據）
  ↓
刷新統計數據（updateMasteryStats, refreshMistakeCount）
```

### 場景 3: 非 VIP 用戶嘗試同步

```
用戶進入設置頁面
  ↓
看到"雲端同步"選項（灰色）
  ↓
點擊選項
  ↓
自動跳轉到 PremiumScreen（訂閱頁面）
```

---

## 📊 數據同步策略

### 上傳到雲端（syncProgressToCloud）

**篩選條件**:
- `user_id = ?` - 當前用戶
- `total_attempts > 0` - 有變動的記錄

**同步字段**:
- `question_id`
- `is_favorite`
- `error_count`
- `wrong_count`
- `is_mastered`
- `correct_streak`
- `total_attempts`
- `last_practiced`
- `synced_at`（服務器時間戳）

### 從雲端恢復（restoreProgressFromCloud）

**合併策略**:
- 如果本地沒有記錄：直接插入雲端數據
- 如果本地有記錄：比較 `last_practiced` 時間戳
  - 雲端較新：使用雲端數據
  - 本地較新：保留本地數據

**優勢**:
- 避免覆蓋本地較新的數據
- 確保數據完整性
- 支持多設備同步

---

## 🔒 VIP 限制實現

### 檢查點

1. **UserStateProvider.syncProgressToCloud()**
   ```dart
   if (!_isVip || _userId == null) {
     throw Exception('僅 VIP 用戶可以使用雲端同步功能');
   }
   ```

2. **SettingsScreen UI**
   ```dart
   if (isLoggedIn && isVip) {
     // 顯示同步按鈕
   } else if (isLoggedIn && !isVip) {
     // 顯示引導訂閱
   }
   ```

3. **DatabaseService.syncProgressToCloud()**
   ```dart
   if (currentUser == null || currentUser.uid != userId) {
     throw Exception('用戶未登入，無法同步到雲端');
   }
   ```

---

## 🎯 使用示例

### VIP 用戶手動同步

1. 進入設置頁面
2. 點擊"立即同步"按鈕
3. 等待同步完成
4. 查看成功/失敗提示

### VIP 用戶登入後自動恢復

1. 用戶登入
2. 系統自動檢測 VIP 狀態
3. 自動從雲端恢復進度
4. 本地數據與雲端數據合併

### 非 VIP 用戶

1. 進入設置頁面
2. 看到"雲端同步"選項（灰色）
3. 點擊後跳轉到訂閱頁面
4. 升級為 VIP 後可使用同步功能

---

## ⚠️ 注意事項

### 1. 網絡連接
- 同步操作需要網絡連接
- 建議在 Wi-Fi 環境下進行大量數據同步
- 需要處理網絡錯誤和超時

### 2. 數據一致性
- 使用 `last_practiced` 時間戳判斷數據新舊
- 合併策略確保不會丟失數據
- 建議定期手動同步

### 3. 性能考慮
- 使用批量寫入提高效率
- 只同步有變動的記錄（`total_attempts > 0`）
- 大量數據時可能需要較長時間

### 4. 錯誤處理
- 同步失敗時顯示錯誤提示
- 不會影響本地數據
- 可以重試同步操作

---

## ✅ 完成狀態

- [x] 添加 cloud_firestore 依賴
- [x] 實現 `syncProgressToCloud()` 方法
- [x] 實現 `restoreProgressFromCloud()` 方法
- [x] 在 SettingsScreen 中添加同步按鈕（VIP 限制）
- [x] 在登入成功後自動觸發雲端恢復
- [x] 實現 VIP 限制檢查
- [x] 實現錯誤處理和用戶提示
- [x] 代碼檢查通過（無錯誤，僅有警告）

---

## 🔍 測試建議

### 1. VIP 用戶同步測試
- 登入 VIP 帳號
- 在設置頁面點擊"立即同步"
- 確認同步成功提示
- 在 Firestore 控制台驗證數據

### 2. 自動恢復測試
- 在設備 A 上登入並練習
- 登出並在設備 B 上登入
- 確認進度自動恢復
- 驗證數據完整性

### 3. VIP 限制測試
- 使用非 VIP 帳號登入
- 確認設置頁面顯示引導訂閱
- 點擊後跳轉到訂閱頁面

### 4. 數據合併測試
- 在設備 A 上練習題目（更新 last_practiced）
- 在設備 B 上同步舊數據
- 確認設備 A 的數據不會被覆蓋

---

*實現完成時間: 2024年12月*
*下次更新: 根據實際使用反饋進行優化*
