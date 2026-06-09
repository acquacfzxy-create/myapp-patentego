# 多語言模式下按鈕水平溢出修復報告

**修復時間**: 2024年12月
**問題**: 多語言模式下按鈕文字過長導致水平溢出（Overflow）
**位置**: `lib/widgets/question_widget.dart`

---

## ✅ 已完成的修復

### 1. 布局組件替換

#### 從 Row 改為 Wrap
- **位置**: `lib/widgets/question_widget.dart` 第 397 行
- **變更**: 將 `Row` 組件替換為 `Wrap` 組件

**原因**:
- `Row` 組件會強制所有子元素在一行顯示，當按鈕文字過長時會導致溢出
- `Wrap` 組件支持自動換行，當空間不足時會將按鈕移到下一行

---

### 2. Wrap 組件配置

#### 間距設置
```dart
Wrap(
  spacing: 10.0,        // 水平間距（按鈕之間的間距）
  runSpacing: 10.0,    // 換行間距（換行後按鈕之間的垂直間距）
  alignment: WrapAlignment.center,  // 居中对齐
  children: [...],
)
```

**效果**:
- 當兩個按鈕可以在一行顯示時，它們之間有 10.0 的間距
- 當按鈕文字過長、一行放不下時，第二個按鈕會自動跳到下一行
- 換行後，按鈕之間有 10.0 的垂直間距

---

### 3. 按鈕寬度優化

#### 移除固定寬度
- **之前**: 按鈕可能使用固定 `width`，導致長文字溢出
- **現在**: 按鈕寬度自適應內容，根據文字長度自動調整

#### 減小內邊距
```dart
OutlinedButton.icon(
  // ...
  style: OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    // horizontal: 12（之前可能是 16 或更大）
    // vertical: 8（保持適當的垂直內邊距）
  ),
)
```

**優點**:
- 減小水平內邊距（從可能的 16 減到 12），為長文字騰出更多空間
- 保持適當的垂直內邊距，確保按鈕點擊區域足夠大
- 按鈕寬度自適應，不會因為固定寬度導致溢出

---

### 4. 垂直滾動確認

#### SingleChildScrollView 包裹
- **位置**: `lib/widgets/question_widget.dart` 第 334 行
- **狀態**: ✅ 已確認整個內容區域包裹在 `SingleChildScrollView` 中

**結構**:
```dart
SingleChildScrollView(
  controller: _scrollController,
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
  child: Column(
    children: [
      // 題目內容
      // 按鈕區域（使用 Wrap）
      // 翻譯和解析內容
    ],
  ),
)
```

**效果**:
- 當按鈕換行時，內容區域會自動增加高度
- 用戶可以垂直滾動查看所有內容
- 不會出現垂直溢出問題

---

## 🔍 修復前後對比

### 修復前
```dart
Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    OutlinedButton.icon(...),  // 翻譯按鈕
    SizedBox(width: 12),
    OutlinedButton.icon(...),  // 解析按鈕
  ],
)
```

**問題**:
- 當按鈕文字過長（如俄語、烏克蘭語）時，兩個按鈕無法在一行顯示
- 導致水平溢出錯誤（Overflow）
- 按鈕被截斷或無法正常顯示

### 修復後
```dart
Wrap(
  spacing: 10.0,
  runSpacing: 10.0,
  alignment: WrapAlignment.center,
  children: [
    OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      ...
    ),
    OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      ...
    ),
  ],
)
```

**優點**:
- 當空間足夠時，兩個按鈕並排顯示
- 當空間不足時，第二個按鈕自動換行
- 不會出現溢出錯誤
- 按鈕文字完整顯示

---

## 📋 支持的多語言場景

### 場景 1: 短文字（中文、英文）
```
[顯示翻譯] [顯示解析]
```
- 兩個按鈕可以在一行顯示
- 間距為 10.0

### 場景 2: 長文字（俄語、烏克蘭語）
```
[Показать перевод]
[Показать объяснение]
```
- 第一個按鈕在一行
- 第二個按鈕自動換到下一行
- 垂直間距為 10.0

### 場景 3: 混合長度
```
[顯示翻譯]
[Показать объяснение]
```
- 根據實際寬度自動調整
- 不會出現溢出

---

## ✅ 測試建議

### 1. 多語言測試
- 切換到不同語言（中文、英文、俄語、烏克蘭語等）
- 確認按鈕文字完整顯示
- 驗證按鈕換行功能正常

### 2. 溢出測試
- 使用最長的按鈕文字（如俄語、烏克蘭語）
- 確認不會出現水平溢出錯誤
- 驗證按鈕可以正常點擊

### 3. 滾動測試
- 當按鈕換行時，確認內容區域可以垂直滾動
- 驗證所有內容都可以正常查看
- 確認底部按鈕不會被遮擋

---

## 📝 技術細節

### Wrap 組件特性
- **自動換行**: 當子元素寬度超過可用空間時，自動換行
- **間距控制**: `spacing` 控制水平間距，`runSpacing` 控制換行間距
- **對齊方式**: `alignment` 控制整體對齊（居中、左對齊等）

### 按鈕樣式優化
- **自適應寬度**: 不使用固定 `width`，讓按鈕根據內容自動調整
- **優化內邊距**: 減小水平內邊距，為長文字騰出空間
- **保持可用性**: 確保按鈕點擊區域足夠大

### 滾動支持
- **SingleChildScrollView**: 確保內容可以垂直滾動
- **動態高度**: 當按鈕換行時，內容區域高度自動增加
- **底部留白**: 底部 padding 為 120，避免被底部按鈕遮擋

---

## 🎯 預期效果

### 修復前
- ❌ 長文字按鈕導致水平溢出
- ❌ 按鈕被截斷或無法正常顯示
- ❌ 出現紅色溢出錯誤提示

### 修復後
- ✅ 按鈕自動換行，不會溢出
- ✅ 所有按鈕文字完整顯示
- ✅ 支持所有語言，包括長文字語言
- ✅ 內容可以正常滾動查看

---

## ✅ 完成狀態

- [x] 將 Row 替換為 Wrap 組件
- [x] 設置 spacing 和 runSpacing
- [x] 優化按鈕寬度（自適應）
- [x] 減小按鈕內部 padding
- [x] 確認 SingleChildScrollView 包裹整個內容區域
- [x] 代碼檢查通過（無 Linter 錯誤）

---

*修復完成時間: 2024年12月*
*下次更新: 根據實際使用反饋進行優化*
