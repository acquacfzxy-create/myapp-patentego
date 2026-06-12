# 多語言關鍵詞生成腳本更新報告

**更新時間**: 2024年12月
**腳本**: `generate_keywords_with_gemini.py`
**功能**: 支持全語種關鍵詞翻譯生成

---

## ✅ 已完成的更新

### 1. Prompt 優化

#### 新增多語言要求
- **支持語言**: 中文 (zh)、英文 (en)、俄語 (ru)、烏克蘭語 (uk)、旁遮普語 (pa)、烏爾都語 (ur)
- **格式要求**: 每個關鍵詞必須包含所有 7 種語言的翻譯

#### 更新後的 Prompt 特點
- 明確要求提供所有語言的翻譯
- 強調翻譯質量，特別是交通術語的專業翻譯
- 保持原有的關鍵詞提取邏輯（1-3 個關鍵詞）

---

### 2. 數據結構更新

#### 新格式
```json
[
  {
    "it": "carreggiata",
    "zh": "车行道",
    "en": "carriageway",
    "ru": "проезжая часть",
    "uk": "проїжджа частина",
    "pa": "ਸੜਕ",
    "ur": "سڑک"
  }
]
```

#### 驗證邏輯
- 檢查每個關鍵詞是否包含所有 7 種語言
- 如果缺少某些語言，會使用空字符串填充（向後兼容）
- 如果只有 `it` 和 `zh`，也會接受（但會標記為不完整）

---

### 3. 斷點續傳和覆蓋邏輯

#### 強制更新模式
- 新增 `force_update` 參數
- 運行時會詢問是否強制更新所有題目
- 如果選擇 `y`，會覆蓋所有現有數據（包括完整的關鍵詞）

#### 增量更新模式（默認）
- 只更新缺失關鍵詞的題目
- 檢查是否包含所有必需語言
- 如果缺少任何語言（en, ru, uk, pa, ur），也會更新

#### 查詢邏輯
```sql
-- 檢查是否需要更新的條件
WHERE (
    q.keywords_json IS NULL
    OR q.keywords_json = ''
    OR q.keywords_json = '[]'
    OR q.keywords_json NOT LIKE '%"en"%'
    OR q.keywords_json NOT LIKE '%"ru"%'
    OR q.keywords_json NOT LIKE '%"uk"%'
    OR q.keywords_json NOT LIKE '%"pa"%'
    OR q.keywords_json NOT LIKE '%"ur"%'
)
```

---

### 4. 統計功能更新

#### 更新 `count_remaining_questions()`
- 支持強制更新模式的統計
- 在強制更新模式下，統計所有題目
- 在增量模式下，統計需要更新的題目（包括缺少語言的）

---

## 🔧 使用方法

### 基本使用（增量更新）

```bash
cd /path/to/assets
# 先在本机 shell 中设置 GEMINI_API_KEY 环境变量
python3 maintenance/scripts/generate_keywords_with_gemini.py
```

運行時會詢問：
```
❓ 是否强制更新所有题目（覆盖旧数据）？
   - 输入 'y' 或 'yes'：强制更新所有 7139 道题
   - 输入其他或直接回车：只更新缺失或缺少语言的题目
   请选择:
```

### 強制更新所有題目

輸入 `y` 或 `yes`，腳本會：
1. 處理所有 7139 道題
2. 覆蓋現有的關鍵詞數據
3. 為每道題生成包含所有 7 種語言的關鍵詞

### 增量更新（推薦）

直接回車或輸入其他內容，腳本會：
1. 只處理缺失關鍵詞的題目
2. 檢查現有數據是否包含所有語言
3. 如果缺少任何語言，也會更新

---

## 📊 處理流程

### 1. 初始化
- 檢查數據庫文件是否存在
- 初始化 Gemini API 客戶端
- 連接數據庫
- 檢查並添加 `keywords_json` 字段

### 2. 統計和選擇模式
- 統計需要處理的題目數量
- 詢問是否強制更新
- 根據選擇設置處理模式

### 3. 批量處理
- 每批處理 50 道題（可配置）
- 對每道題：
  1. 調用 Gemini API 生成關鍵詞
  2. 驗證返回格式（必須包含所有 7 種語言）
  3. 更新數據庫

### 4. 進度追蹤
- 實時顯示處理進度
- 顯示成功/失敗統計
- 顯示剩餘題目數量

---

## ⚙️ 配置參數

### 批次設置
```python
BATCH_SIZE = 50  # 每批處理的題目數量
DELAY_BETWEEN_BATCHES = 5  # 批次之間的延遲（秒）
DELAY_BETWEEN_REQUESTS = 4  # 單個請求之間的延遲（秒）
MAX_REQUESTS_PER_MINUTE = 12  # 每分鐘最大請求數
```

### API 配置
```python
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
model = genai.GenerativeModel('gemini-2.0-flash')
```

---

## 🔍 驗證邏輯

### 必需語言列表
```python
required_languages = ['it', 'zh', 'en', 'ru', 'uk', 'pa', 'ur']
```

### 驗證步驟
1. 檢查返回的是否為列表格式
2. 檢查每個元素是否為字典
3. 檢查是否包含所有 7 種語言
4. 如果缺少語言，使用空字符串填充（向後兼容）

---

## 📝 注意事項

### 1. API 速率限制
- 腳本已實現速率限制保護
- 每分鐘最多 12 個請求
- 如果遇到 429 錯誤，會自動等待並重試

### 2. 數據覆蓋
- **強制更新模式**：會覆蓋所有現有數據
- **增量更新模式**：只更新缺失或缺少語言的題目
- 建議先使用增量模式測試，確認無誤後再使用強制更新

### 3. 翻譯質量
- Gemini API 會自動生成翻譯
- 建議處理完成後抽查部分題目，確認翻譯質量
- 如有問題，可以重新運行腳本更新特定題目

### 4. 斷點續傳
- 腳本支持中斷後繼續執行
- 已處理的題目不會重複處理（除非使用強制更新模式）
- 可以隨時中斷（Ctrl+C），下次運行會繼續處理剩餘題目

---

## 🎯 預期結果

### 處理完成後
- 所有 7139 道題都包含關鍵詞數據
- 每個關鍵詞包含 7 種語言的翻譯：
  - `it`: 意大利語（原始）
  - `zh`: 中文
  - `en`: 英文
  - `ru`: 俄語
  - `uk`: 烏克蘭語
  - `pa`: 旁遮普語
  - `ur`: 烏爾都語

### 數據格式示例
```json
[
  {
    "it": "carreggiata",
    "zh": "车行道",
    "en": "carriageway",
    "ru": "проезжая часть",
    "uk": "проїжджа частина",
    "pa": "ਸੜਕ",
    "ur": "سڑک"
  },
  {
    "it": "sorpasso",
    "zh": "超车",
    "en": "overtaking",
    "ru": "обгон",
    "uk": "обгін",
    "pa": "ਓਵਰਟੇਕਿੰਗ",
    "ur": "اوورٹیکنگ"
  }
]
```

---

## 🔄 後續步驟

### 1. 執行腳本
```bash
cd /path/to/assets
# 先在本机 shell 中设置 GEMINI_API_KEY 环境变量
python3 maintenance/scripts/generate_keywords_with_gemini.py
```

### 2. 選擇更新模式
- 首次運行：建議使用增量更新模式
- 如果需要覆蓋所有數據：選擇強制更新模式

### 3. 監控進度
- 腳本會實時顯示處理進度
- 可以隨時中斷（Ctrl+C）
- 下次運行會自動繼續

### 4. 驗證結果
處理完成後，可以運行以下 SQL 查詢驗證：
```sql
-- 檢查所有題目是否都有關鍵詞
SELECT COUNT(*) FROM questions
WHERE keywords_json IS NOT NULL
AND keywords_json != ''
AND keywords_json != '[]';

-- 檢查是否包含所有語言
SELECT COUNT(*) FROM questions
WHERE keywords_json LIKE '%"en"%'
AND keywords_json LIKE '%"ru"%'
AND keywords_json LIKE '%"uk"%'
AND keywords_json LIKE '%"pa"%'
AND keywords_json LIKE '%"ur"%';
```

---

## ✅ 完成狀態

- [x] Prompt 更新為支持全語種翻譯
- [x] 數據結構驗證更新
- [x] 斷點續傳邏輯完善
- [x] 強制更新模式實現
- [x] 增量更新模式優化
- [x] 統計功能更新
- [x] 代碼檢查通過（無 Linter 錯誤）

---

*更新完成時間: 2024年12月*
*下次更新: 根據實際使用反饋進行優化*
