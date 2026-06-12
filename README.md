# 義大利駕照測驗 App (Flutter)

基於 Flutter 開發的義大利駕照理論測驗移動應用程序，具有高度的可擴展性設計。

## 項目結構

```
lib/
├── main.dart                      # 應用入口
├── models/                        # 數據模型
│   ├── question.dart             # 題目模型（支持多語言）
│   └── user_state.dart           # 用戶狀態模型
├── services/                      # 業務邏輯服務
│   └── database_service.dart     # 數據庫服務（雙庫邏輯）
├── screens/                       # 頁面
│   ├── home_screen.dart          # 首頁
│   ├── practice_screen.dart      # 練習模式
│   ├── mock_test_screen.dart     # 模擬考試
│   ├── mock_test_result_screen.dart  # 考試結果
│   ├── settings_screen.dart      # 設置頁面
│   └── premium_screen.dart       # 會員訂閱頁面
├── widgets/                       # 可復用組件
│   └── question_widget.dart      # 題目顯示組件
└── config/                        # 配置文件
    ├── app_config.dart           # 應用配置（付費邏輯）
    └── mock_test_config.dart     # 模擬考試配置
```

## 核心特性

### 1. 數據模型設計

- **Question 模型** (`lib/models/question.dart`)
  - 支持多語言題目內容 (`Map<String, String> translations`)
  - 支持多語言解析 (`Map<String, String> explanations`)
  - 靈活的圖片路徑處理

- **UserState 模型** (`lib/models/user_state.dart`)
  - 付費狀態管理 (`isPremium`)
  - 當前語言設置 (`currentLanguage`)
  - 支持多語言切換

### 2. 數據庫服務（雙庫邏輯）

- **主數據庫**（只讀）：從 assets 複製的題庫數據庫
  - `questions` 表：題目基本信息
  - `translations` 表：多語言翻譯

- **用戶進度數據庫**（可讀寫）：記錄用戶學習進度
  - `user_progress` 表：
    - `question_id`: 題目ID
    - `is_favorite`: 是否收藏
    - `error_count`: 錯誤次數
    - `last_practiced`: 最後練習時間

### 3. 功能模塊

#### 練習模式
- 隨機題目練習
- 實時統計答題數和錯誤數
- 收藏功能
- 題目解析顯示

#### 模擬考試
- 30 題模擬考試
- 20 分鐘倒計時（最後5分鐘變紅提醒）
- 錯3題合格標準
- 考試結果統計

#### 設置功能
- 語言切換（支持多種語言）
- 付費狀態查看
- 會員訂閱入口

### 4. 商業模式預留

- **AppConfig** (`lib/config/app_config.dart`)
  - 全局付費狀態管理
  - 章節鎖定邏輯（免費用戶限制訪問章節數）
  - 未來可擴展支付 SDK 集成

## 技術棧

- Flutter 3.0+
- sqflite - SQLite 數據庫支持
- path, path_provider - 文件路徑管理
- Material Design 3

## 安裝和運行

1. 確保已安裝 Flutter SDK（3.0+）

2. 安裝依賴：
```bash
flutter pub get
```

3. 確保數據庫文件在正確位置：
   - `italy_quiz.db` 應該在項目根目錄
   - 已在 `pubspec.yaml` 中配置為 assets

4. 運行應用：
```bash
flutter run
```

## 模擬考試規則

- **題目數量**：30 題
- **時間限制**：20 分鐘
- **評分標準**：最多允許 3 題錯誤，超過則不及格

## 擴展性設計

### 添加新語言

1. 在 `UserState.supportedLanguages` 中添加語言代碼
2. 在 `UserState.languageNames` 中添加語言顯示名稱
3. 確保數據庫 `translations` 表中有對應語言的翻譯數據

### 添加章節功能

1. 在數據庫中添加 `chapter_id` 字段（如果尚未添加）
2. 在 `DatabaseService.getQuestions()` 中啟用章節過濾邏輯
3. 創建章節選擇頁面
4. 使用 `AppConfig.isChapterLocked()` 檢查章節鎖定狀態

### 集成支付功能

1. 添加支付 SDK（如 `in_app_purchase`）
2. 在 `PremiumScreen` 中實現實際支付邏輯
3. 支付成功後調用 `AppConfig.setPremium(true)`
4. 使用 `SharedPreferences` 持久化付費狀態

### 狀態管理擴展

當前設計已預留狀態管理接口，可以輕鬆集成：
- Provider
- GetX
- Riverpod
- Bloc

## 開發說明

### 數據庫初始化

應用首次啟動時，會自動將 `assets/italy_quiz.db` 複製到應用的文檔目錄。用戶進度數據庫會在首次使用時自動創建。

### 圖片資源

題目圖片路徑存儲在數據庫的 `img` 字段中。如果圖片是本地資源，需要將圖片放在 `assets/` 目錄下，並在 `pubspec.yaml` 中註冊。

### 語言切換

當前語言設置需要在實際應用中與全局狀態管理集成，或使用 `SharedPreferences` 持久化。代碼中已預留接口。

## 版本歷史

- v1.0.0 - 初始版本
  - 基礎練習和模擬考試功能
  - 多語言支持
  - 用戶進度記錄
  - 付費功能預留
