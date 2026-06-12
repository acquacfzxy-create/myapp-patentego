# Codex 接班人說明書 — Patentego / Italy Quiz App

本文件供 **OpenAI Codex**（CLI / IDE 擴充 / App）在接手本倉庫時自動載入。
維護者從 **Cursor** 遷移而來；請把本檔視為「專案憲法 + 營運手冊」。

---

## 1. 專案是什麼

| 項目 | 說明 |
|------|------|
| **產品** | 義大利駕照理論測驗 App（Flutter） |
| **套件名** | `italy_quiz_app`（`pubspec.yaml`） |
| **商店包名** | Android/iOS：`com.patentego.app` |
| **工作目錄** | `/Users/fabio/Desktop/assets`（倉庫根） |
| **題庫規模** | 約 **7139** 題（以 `questions` 表為準） |

**核心能力**：章節練習、模擬考、錯題複習、收藏、多語言題幹與解析、VIP 訂閱與免費解析次數限制、Firebase 登入與 Firestore 進度同步。

---

## 2. 目錄地圖（改碼前先找對檔）

```
lib/
  main.dart                 # 入口：Firebase、DatabaseService.init、Provider
  config/
    app_config.dart         # 免費章節數、VIP 鎖章邏輯
    app_strings.dart        # 全 App UI 多語言字串（含 study_tip_title 等）
    chapter_config.dart     # 章節元數據
  models/
    question.dart           # 題目模型；解析可為純文本或 JSON
    user_state.dart
  providers/
    user_state_provider.dart  # VIP、語言、免費解析次數等
  services/
    database_service.dart   # ★ 最大檔：雙庫、查題、同步、VIP（~3100 行）
  screens/                  # 各頁面（home、practice、mock_test、subscription…）
  widgets/
    question_widget.dart    # 題目 UI + showRichExplanation 解析彈窗

assets/
  italy_quiz.db             # ★ 內建題庫（隨 App 打包，維護腳本會直接改此檔）

images/img_sign/            # 題目配圖（與 DB `questions.img` 對應）

maintenance/scripts/        # ★ Python 維護腳本（解析生成、章節、關鍵詞等）
scripts/                    # 部分腳本轉發入口（見 generate_global_explanations.py）

ios/ android/               # 原生工程；Firebase 配置已接入
```

**不要**在無需求時重構 `database_service.dart` 全檔；優先局部修改並跑 `flutter analyze`。

---

## 3. 數據與解析格式

### 3.1 雙庫

- **主庫**（只讀副本）：`assets/italy_quiz.db` → 複製到應用文件目錄
  - `questions`：題幹、答案、`img`、章節等
  - `translations`：`type='q'` 題幹翻譯，`type='e'` **解析**
- **進度庫**（可寫）：`user_progress.db`
  - `user_progress`：收藏、`wrong_count`、掌握度等；`user_id` 含 `guest_user`

更新內建題庫後，須遞增 `DatabaseService.kStaticDbVersion`（目前 **8**），否則已安裝用戶可能看不到新題。

### 3.2 解析 JSON（`translations.type='e'`）

六種目標語言（**不含**意大利語 `it`）：`zh`, `en`, `ru`, `uk`, `pa`, `ur`。

```json
{
  "detailed_description": "一到兩句判題邏輯",
  "key_points": [
    {"title": "義大利語詞或短語", "content": "該語言一句短白話"},
    {"title": "...", "content": "..."}
  ],
  "study_tip": "教練口吻私房話；可含 **義大利詞 (翻譯)** Markdown 粗體"
}
```

- **`zh` 必須為大陸簡體中文**（个、这、实际），禁止繁體（個、這、實際）混入定稿。
- 禁用舊模板口吻：`【】`、`公式`、`秒殺`、`破解`、`三段式` 等（腳本會觸發整題重刷）。
- App 端：`QuestionWidget.showRichExplanation` 解析 JSON；`study_tip` 支援 `**粗體**` 與對/錯關鍵字高亮（見 `buildStudyTipMarkdownSpan`，注意勿誤高亮「针对」「对不对」內的「对」）。

---

## 4. 常用命令

### Flutter

```bash
cd /Users/fabio/Desktop/assets
flutter pub get
flutter analyze
flutter test                    # 若有測試
flutter run                     # 真機/模擬器
```

### 全庫解析生成（Gemini，長時間）

**腳本**：`maintenance/scripts/generate_global_explanations.py`
（捷徑：`python3 scripts/generate_global_explanations.py` → 轉發到上述路徑）

**環境**（禁止寫入 repo 或 commit）：

```bash
export GEMINI_API_KEY="你的金鑰"
pip3 install google-generativeai pillow
```

| 場景 | 命令 |
|------|------|
| **全庫強制重刷「自然教練版」** | `python3 -u maintenance/scripts/generate_global_explanations.py --force --limit 0` |
| 只補缺語言 / 舊模板 | `--retry-incomplete`（不帶 `--force` 時只補洞） |
| 重試失敗題號 | `--retry-failed`（題號在 `failed_ids.txt`） |
| 抽查 N 題 | `--limit 5`（預設 **100**，全庫務必 `--limit 0`） |

**節奏**：每題 A/B 兩次 API，組間 10s，成功後隨機 **15–20s**；連續 3 題 429 熔斷退出。
**輸出**：`response_mime_type=application/json`；`study_tip` 內引用題幹請用「」勿用未轉義 `"`。

**背景長跑**：

```bash
nohup python3 -u maintenance/scripts/generate_global_explanations.py --force --limit 0 >> data_sync.log 2>&1 &
```

**監控**：

```bash
tail -f data_sync.log
grep '进度:' data_sync.log | tail -n 5
grep 'GOLDEN DATABASE READY' data_sync.log
pgrep -fl generate_global_explanations
```

完成條件：`--force` 跑滿排隊題數且 API 失敗率 **< 1%** 時，日誌末尾會印 **`GOLDEN DATABASE READY`**。

**其他維護腳本**（按需查 `maintenance/scripts/README_*.md`）：

- `normalize_zh_explanations.py` — 簡繁/術語校正
- `generate_keywords_with_gemini.py` — 關鍵詞
- `database_health_check.py` — 題庫健康檢查

---

## 5. 與維護者協作規則（必讀）

1. **回覆語言**：與維護者溝通使用 **繁體中文**（程式註釋可沿用既有簡/繁混用，但新增 `zh` 題庫內容必須簡體）。
2. **Git**：**僅在維護者明確要求時** `git commit` / `push`；不要 `--no-verify`、不要 `force push main`。
3. **範圍**：只改與任務相關的檔案；禁止順手大規模格式化或無關重構。
4. **密鑰**：`GEMINI_API_KEY`、Firebase、商店密鑰 **不得** 寫入源碼、日誌範例或 commit。
5. **大檔**：改 `database_service.dart` / `question_widget.dart` 前先讀周邊上下文，保持命名與 Provider 模式一致。
6. **數據庫**：跑批量腳本前提醒備份 `assets/italy_quiz.db`；腳本執行中避免 Flutter 同時寫入。
7. **完成定義**：功能改動 → `flutter analyze` 通過；腳本改動 → `python3 -m py_compile` 相關檔；解析任務 → 對應題 `type='e'` 六語 JSON 可 `json.loads`。

---

## 6. 產品與商業邏輯摘要

- **免費用戶**：`AppConfig.freeChapterLimit = 2` 章節後鎖定；解析有每日免費次數（`UserStateProvider.remainingExplanations`）。
- **VIP**：`isVip` 來自訂閱 + Firestore `users/{uid}.isVip`；非 VIP 在 `study_tip` 區塊顯示可點擊 **✨ VIP** 標籤（`SubscriptionPage`）。
- **登入**：Google / Apple + `firebase_options.dart`；訪客進度可合併到帳號（`mergeGuestDataToAccount`）。
- **模擬考**：約 30 題、錯 3 題內合格（見 `mock_test_config.dart` 與相關 screen）。

---

## 7. 近期技術債與注意點

| 主題 | 說明 |
|------|------|
| `google.generativeai` | 已棄用警告；腳本仍用此套件，勿在未評估前整庫遷 `google.genai` |
| 解析重刷 | 全庫 `--force` 約 **50+ 小時**；中斷可從日誌題號 + `failed_ids.txt` 續跑 |
| JSON 截斷 | 若見 `Expecting ',' delimiter`，多為 `study_tip` 內未轉義 `"`；已用 JSON MIME + Prompt 約束，改腳本後需 **重啟 nohup** |
| README 過時 | 根目錄 `README.md` / `README_global_explanations.md` 部分參數已舊，以 **腳本內常數與本檔** 為準 |
| Linter | `question_widget.dart` 可能有未使用符號警告（`_scrollToBottom` 等），非本次任務勿順手刪除非確認 |

---

## 8. 任務提示模板（給 Codex 用）

複製並填寫：

```
目標：（一句話）
涉及檔案/目錄：（如 lib/widgets/question_widget.dart）
約束：不 commit；繁體回覆；zh 解析用簡體
完成條件：flutter analyze 通過 / 日誌出現 XXX
```

複雜任務先 **`/plan`** 或要求先出計劃再改碼。多步驟資料任務與 UI 任務 **分 thread**。

---

## 9. 延伸閱讀

- `maintenance/scripts/README_global_explanations.md` — 解析腳本入門（部分過時）
- `maintenance/scripts/generate_global_explanations.py` — 權威邏輯（Prompt、429、force、GOLDEN）
- `lib/widgets/question_widget.dart` — `showRichExplanation`、`buildStudyTipMarkdownSpan`
- [Codex AGENTS.md 指南](https://developers.openai.com/codex/guides/agents-md)

---

*最後更新：接手自 Cursor 工作流；專案路徑 `/Users/fabio/Desktop/assets`。*
