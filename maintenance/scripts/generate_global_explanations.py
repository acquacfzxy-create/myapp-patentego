#!/usr/bin/env python3
"""
使用 Google Gemini API 批量生成多语言结构化题目解析（极致省钱模式）
批量处理 italy_quiz.db 数据库中的所有题目
"""

import argparse
import atexit
import json
import os
import random
import re
import signal
import sqlite3
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

# 使用 google.generativeai（與官方範例一致；模型名用無 models/ 前綴的字串）
try:
    from PIL import Image as PILImage
except ImportError:
    PILImage = None  # type: ignore[misc, assignment]

try:
    import google.generativeai as genai
except ImportError:
    print("❌ 错误：未安装 google-generativeai")
    print("请运行: pip3 install google-generativeai")
    print("或升级: pip3 install --upgrade google-generativeai")
    sys.exit(1)

# 配置（腳本位於 maintenance/scripts/，倉庫根為上兩級）
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
DATABASE_PATH = PROJECT_ROOT / "assets" / "italy_quiz.db"

print(f"🔍 [Config] 脚本目录: {SCRIPT_DIR}")
print(f"🔍 [Config] 项目根目录: {PROJECT_ROOT}")
print(f"🔍 [Config] 数据库路径: {DATABASE_PATH}")
print(f"🔍 [Config] 数据库文件存在: {DATABASE_PATH.exists()}")

# 批次配置
BATCH_SIZE = 5  # 每批处理的题目数量（建议5题以节省Token）
# 成功處理一題後隨機等待（秒），單請求慢節奏、降低 TPM／封號風險
POST_SUCCESS_SLEEP_SEC_MIN = 15.0
POST_SUCCESS_SLEEP_SEC_MAX = 20.0
# 固定模式下不做動態加速，保留為 0 供統一計算
POST_SUCCESS_DYNAMIC_BACKOFF_SEC = 0
# A/B 組之間固定冷卻
INTER_GROUP_SLEEP_SEC = 10
MAX_429_RECOVERY_ROUNDS = 5  # 429 指數退避最多冷卻+重試輪數（首輪 60 秒起算）
# 熔斷：連續 3 道題都在 429 退避耗盡後失敗，則安全退出
CIRCUIT_BREAKER_CONSECUTIVE_429_FAILURES = 3
BATCH_LIMIT = None  # 每次运行最多处理的题目数量（None = 无限制，处理所有题目）
# 單次執行預設最多處理題數（可用 --limit 0 關閉上限）
DEFAULT_RUN_LIMIT = 100

# 最終仍失敗的題目 ID（429 耗盡退避後仍失敗等）
failed_ids: List[str] = []
FAILED_IDS_PATH = PROJECT_ROOT / "failed_ids.txt"


def _write_failed_ids_file() -> None:
    """將 failed_ids 寫入專案根目錄（正常結束、atexit、Ctrl+C 均會觸發）。"""
    try:
        with open(FAILED_IDS_PATH, "w", encoding="utf-8") as f:
            for qid in failed_ids:
                f.write(f"{qid}\n")
        if failed_ids:
            print(f"\n📝 已寫入失敗題目列表: {FAILED_IDS_PATH}（共 {len(failed_ids)} 條）")
    except OSError as e:
        print(f"\n⚠️ 寫入 {FAILED_IDS_PATH} 失敗: {e}")


def _reset_failed_ids_file() -> None:
    """啟動時重置失敗記錄，避免舊模型錯誤污染新一輪執行。"""
    global failed_ids
    failed_ids = []
    try:
        with open(FAILED_IDS_PATH, "w", encoding="utf-8"):
            pass
        print(f"🧹 已重置失败记录: {FAILED_IDS_PATH}")
    except OSError as e:
        print(f"⚠️ 无法重置 {FAILED_IDS_PATH}: {e}")


def _read_failed_ids_from_file() -> List[str]:
    """
    從專案根目錄 failed_ids.txt 讀取待重試題號（每行一個，去重保序）。
    須在 _reset_failed_ids_file() 之前調用，否則檔案可能已被清空。
    """
    if not FAILED_IDS_PATH.is_file():
        print(f"⚠️  未找到 {FAILED_IDS_PATH}，無失敗題目可重試。")
        return []
    seen: Set[str] = set()
    out: List[str] = []
    try:
        with open(FAILED_IDS_PATH, encoding="utf-8") as f:
            for line in f:
                qid = line.strip()
                if not qid or qid.startswith("#"):
                    continue
                if qid not in seen:
                    seen.add(qid)
                    out.append(qid)
    except OSError as e:
        print(f"⚠️  讀取失敗列表失敗: {e}")
        return []
    print(f"📋 從 {FAILED_IDS_PATH.name} 讀取 {len(out)} 個失敗題目 ID，準備重試…")
    return out


def _on_sigint(_signum: int, _frame: object) -> None:
    print("\n⚠️ 收到中斷 (Ctrl+C)，正在保存 failed_ids...")
    _write_failed_ids_file()
    raise SystemExit(130)


atexit.register(_write_failed_ids_file)
signal.signal(signal.SIGINT, _on_sigint)


def _sleep_post_question_success() -> None:
    """每題成功落盤後的節流等待（15–20 秒隨機）。"""
    delay = random.uniform(
        POST_SUCCESS_SLEEP_SEC_MIN, POST_SUCCESS_SLEEP_SEC_MAX
    ) + POST_SUCCESS_DYNAMIC_BACKOFF_SEC
    time.sleep(delay)


# 目標語言（你需要重刷的 6 種，不含意大利語 it）
TARGET_LANGUAGES: List[str] = ["zh", "en", "ru", "uk", "pa", "ur"]
LANG_GROUP_A = ["zh", "en"]
LANG_GROUP_B = ["ru", "uk", "pa", "ur"]

# 由 argparse 写入：only_wrong / force / limit
RUN_OPTIONS: Dict[str, object] = {
    "only_wrong": False,
    "force": False,
    "limit": None,  # type: ignore[assignment]
    "start_id": None,  # type: ignore[assignment]
    "retry_failed": False,
    "retry_incomplete": False,
}

# Gemini API：初始化時自動探測可用模型（嚴禁 Pro）
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "").strip()
MODEL_NAME = ""
MODEL_CANDIDATES_PRIORITY: Tuple[str, ...] = (
    "gemini-1.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-2.5-flash",
    "gemini-2.0-flash",
)

model = None
_consecutive_final_429_failures: int = 0


class CircuitBreakerTriggered(Exception):
    """連續 429 最終失敗觸發的安全退出。"""


def _setup_genai_model() -> None:
    """用 list_models 自動選擇可用的低成本 Flash 模型（禁 Pro）。"""
    global model, MODEL_NAME
    print("💡 遇接口异常时可升级: pip3 install --upgrade google-generativeai")
    available: Set[str] = set()
    try:
        for m in genai.list_models():
            name = str(getattr(m, "name", ""))
            methods = getattr(m, "supported_generation_methods", None) or []
            if "generateContent" not in methods:
                continue
            if "pro" in name.lower():
                continue
            if name.startswith("models/"):
                name = name.split("/", 1)[1]
            available.add(name)
    except Exception as e:
        print(f"⚠️ 模型列表获取失败，按优先级直接尝试: {e}")

    chosen = ""
    for cand in MODEL_CANDIDATES_PRIORITY:
        if cand in available:
            chosen = cand
            break
    if not chosen:
        chosen = MODEL_CANDIDATES_PRIORITY[0]
    MODEL_NAME = chosen
    print(f"📌 自动选择模型: {MODEL_NAME!r}")
    model = genai.GenerativeModel(MODEL_NAME)


def _is_model_not_found_error(exc: BaseException) -> bool:
    s = str(exc).lower()
    return "404" in s or "not found" in s or "no longer available" in s


def _switch_to_next_model_candidate() -> bool:
    """當前模型 404 時，按優先序切換到下一個候補模型。"""
    global model, MODEL_NAME
    try:
        idx = MODEL_CANDIDATES_PRIORITY.index(MODEL_NAME)
    except ValueError:
        idx = -1
    next_idx = idx + 1
    if next_idx >= len(MODEL_CANDIDATES_PRIORITY):
        return False
    MODEL_NAME = MODEL_CANDIDATES_PRIORITY[next_idx]
    model = genai.GenerativeModel(MODEL_NAME)
    print(f"🔁 模型 404，自動切換為: {MODEL_NAME}")
    return True

# A/B 組 System Prompt（見下方 PROMPT_BASE）
PROMPT_BASE = """
你是「在義大利生活多年、極其幽默又專業」的華人駕校教練，專門帶意語不好的學生考義大利駕照。
語氣要自然、直白、口語化，像在跟好朋友講題；可以輕鬆幽默，但不要油膩、不要堆砌術語。

輸出要求（必須嚴格遵守）：
- 只輸出一個純 JSON 字串，嚴禁 Markdown、嚴禁 ```json 或 ``` 包圍。
- 每個目標語言都必須包含鍵：detailed_description、key_points（長度 2 的陣列）、study_tip。
- **JSON 字串內嚴禁夾雜未轉義的英文雙引號 "**：例如在 study_tip 裡引用題幹時，不要用 `"雙向車道"` 這種寫法（會截斷 JSON、導致解析失敗）。請改用中文直角引號「」『』包圍引文，或改寫成不帶引號，或把內部雙引號寫成 \\"（反斜線+雙引號）。

內容結構：
- detailed_description：用該語言寫一到兩句話，點出本題判題邏輯（結論 + 為什麼），不要抄題幹。
- study_tip（核心「私房話」）：一段自然口語，像教練在耳邊提醒；語氣要**專業且親切**。**嚴禁**出現孤立、無承接的句末語氣碎片（例如單獨的「吧？」「呢？」等懸空標點或半截感嘆問句）。每一句邏輯要連貫通順，重點在於說清**題目陷阱**（易錯點、題幹誤導、常見混淆）以及為何如此判斷。
  **必須**把至少一個義大利語關鍵詞，用「**義大利詞 (母語翻譯)**」這種形式自然地嵌進句子裡（不要列標題、不要分段模板）。
  風格參考（不可照抄，須依題改寫）：你要盯著 **obbligatorio（強制）** 這個詞。紅圈是禁止，藍圈才是強制；紅圈裡畫拖拉機卻說是強制，那肯定不對。
- key_points：兩筆 {"title":"義大利語詞或短語","content":"該語言一句短白話"}，當作小抄，不要寫成說明書。

語言鍵 zh（簡體中文硬性要求）：
- detailed_description、key_points、study_tip 必須使用中国大陆規範**簡體中文**（例如用「个」「这」「实际」「发现」），**禁止**繁體字與港台繁體字形（例如「個」「這」「實際」「發現」）。若輸出中不慎混入繁體，須在定稿前**自行全文改寫為簡體**後再輸出 JSON。

嚴禁用語（任何語言都不得出現）：破解、秒殺、公式、三段式、套路、必殺、口訣模板 等像說明書的字眼。
嚴禁使用全形或半形方括號標題（【】）或類似章節標籤。

若本輪有附上題目配圖（像素圖）：
- 下筆前先核對圖片內容；若題幹文字與圖片明顯不符，一律以圖片為準寫解析。
- 絕不可幻覺：圖裡是農用車/拖拉機，解析就不能扯到停車讓行之類圖中沒有的標誌。
- 若題目描述特徵與圖片特徵不一致（例如題幹寫棕色背景、圖中卻是綠色背景），
  必須在解析中明確點出這個差異，並說明為何題目判斷仍成立或不成立；不可以假裝沒看到差異。

篇幅：各語種的 detailed_description + study_tip + 兩條 key_points 合計請保持精簡（中文約 120 字內為宜；其他語言等效簡短），避免長篇。
"""
SYSTEM_PROMPT_GROUP_A = PROMPT_BASE + "\n僅生成語言鍵：zh、en。"
SYSTEM_PROMPT_GROUP_B = PROMPT_BASE + "\n僅生成語言鍵：ru、uk、pa、ur。"


# 任一語種 type=e 原始字串若含下列片段，視為舊模板／非「自然教練版」，應整題重刷
# （與 _get_missing_target_languages、_question_has_all_target_lang_explanations 共用）
_LEGACY_TEMPLATE_SUBSTRINGS: Tuple[str, ...] = (
    "【",
    "公式",
    "秒殺",
    "秒杀",
    "破解",
    "三段式",
)


def _explanation_raw_contains_legacy_template(raw: str) -> bool:
    """檢查該語種 type=e 的原始內容是否含舊模板標記（不僅看是否為合法 JSON）。"""
    if not raw or not str(raw).strip():
        return False
    t = str(raw)
    return any(s in t for s in _LEGACY_TEMPLATE_SUBSTRINGS)


def _zh_explanation_json_needs_legacy_refresh(zh_raw: str) -> bool:
    """向後兼容別名：舊名稱仍指向同一套模板檢測。"""
    return _explanation_raw_contains_legacy_template(zh_raw)


def _resolve_question_image_path(img_name: Optional[str]) -> Optional[Path]:
    """將資料庫 img 欄位轉為本機圖檔路徑（若存在）。"""
    if not img_name or not str(img_name).strip():
        return None
    raw = str(img_name).strip()
    if raw.startswith("/"):
        raw = raw[1:]
    for base in (PROJECT_ROOT / "images", PROJECT_ROOT / "assets" / "images"):
        p = base / raw
        if p.is_file():
            return p
    return None


def get_db_connection():
    """获取数据库连接"""
    if not DATABASE_PATH.exists():
        raise FileNotFoundError(f"数据库文件不存在: {DATABASE_PATH}")
    # timeout：寫入遇鎖時等待釋放，降低 database is locked 立即失敗
    return sqlite3.connect(str(DATABASE_PATH), timeout=120.0)


def _question_has_all_target_lang_explanations(
    conn: sqlite3.Connection, question_id: str
) -> bool:
    """
    斷點續傳：是否已為該題寫入 TARGET_LANGUAGES 中全部語種的 type='e'、可解析 JSON，
    且不含舊模板標籤（如「【」）。
    （未帶 --force 時跳過，避免重複消耗 TPM）
    """
    cursor = conn.cursor()
    for lang in TARGET_LANGUAGES:
        cursor.execute(
            """
            SELECT content FROM translations
            WHERE question_id = ? AND lang = ? AND type = 'e' LIMIT 1
            """,
            (question_id, lang),
        )
        row = cursor.fetchone()
        if not row or not row[0]:
            return False
        raw = str(row[0]).strip()
        if not raw.startswith("{"):
            return False
        if _explanation_raw_contains_legacy_template(raw):
            return False
        try:
            json.loads(raw)
        except json.JSONDecodeError:
            return False
    return True


def _get_missing_target_languages(conn: sqlite3.Connection, question_id: str) -> List[str]:
    """
    返回該題尚缺失的目標語言。
    完成條件：type='e'、可解析 JSON，且原始內容不含舊模板標籤（如「【」、秒殺等）。
    任一目標語種若含舊模板，整題視為需重刷，回傳全部語種鍵。
    （--force 時由外層直接指定六語全生成，仍依賴此邏輯做非 force 的斷點與翻新判斷。）
    """
    cursor = conn.cursor()
    for lang in TARGET_LANGUAGES:
        cursor.execute(
            """
            SELECT content FROM translations
            WHERE question_id = ? AND lang = ? AND type = 'e' LIMIT 1
            """,
            (question_id, lang),
        )
        row = cursor.fetchone()
        if row and row[0] and _explanation_raw_contains_legacy_template(str(row[0])):
            return TARGET_LANGUAGES[:]

    missing: List[str] = []
    cursor = conn.cursor()
    for lang in TARGET_LANGUAGES:
        cursor.execute(
            """
            SELECT content FROM translations
            WHERE question_id = ? AND lang = ? AND type = 'e' LIMIT 1
            """,
            (question_id, lang),
        )
        row = cursor.fetchone()
        if not row or not row[0]:
            missing.append(lang)
            continue
        raw = str(row[0]).strip()
        if not raw.startswith("{"):
            missing.append(lang)
            continue
        try:
            json.loads(raw)
        except json.JSONDecodeError:
            missing.append(lang)
    return missing


def _is_resource_exhausted_error(exc: BaseException) -> bool:
    """判斷是否為 Gemini / Google API 429 或 RESOURCE_EXHAUSTED 限流。"""
    s = str(exc)
    if "429" in s:
        return True
    if "RESOURCE_EXHAUSTED" in s.upper():
        return True
    try:
        from google.api_core import exceptions as g_exc  # type: ignore

        if isinstance(exc, g_exc.ResourceExhausted):
            return True
    except Exception:
        pass
    return False


def _ensure_db_alive(conn: sqlite3.Connection) -> sqlite3.Connection:
    """長時間等待前後檢查連線；若已斷開則關閉並新建連線。"""
    try:
        conn.execute("SELECT 1").fetchone()
        return conn
    except sqlite3.Error:
        try:
            conn.close()
        except Exception:
            pass
        print("   🔌 資料庫連線已失效，正在重新連線...")
        return get_db_connection()


def _get_wrong_question_ids(limit: Optional[int] = None) -> List[str]:
    """
    優先隊列：從 user_progress 中讀取 wrong_count > 0 的題目 ID 列表。
    - 如果數據庫中不存在 user_progress 表或 wrong_count 字段，則返回空列表（完全後向兼容）。
    - 只返回 question_id，不做去重以外的任何修改。
    """
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        # 檢查 user_progress 表是否存在
        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='user_progress'"
        )
        if cursor.fetchone() is None:
            return []

        # 檢查是否存在 wrong_count 欄位
        cursor.execute("PRAGMA table_info(user_progress)")
        columns = cursor.fetchall()
        has_wrong_count = any(col[1] == "wrong_count" for col in columns)
        if not has_wrong_count:
            return []

        base_sql = """
            SELECT DISTINCT question_id
            FROM user_progress
            WHERE wrong_count > 0
            ORDER BY wrong_count DESC, CAST(question_id AS INTEGER)
        """
        if limit is not None:
            base_sql += " LIMIT ?"
            cursor.execute(base_sql, (limit,))
        else:
            cursor.execute(base_sql)

        rows = cursor.fetchall()
        return [row[0] for row in rows]
    finally:
        conn.close()


def get_questions_with_missing_explanations() -> List[Tuple[str, str, bool, Optional[str]]]:
    """全庫模式：按題號升序讀取全題庫（含配圖 img 欄位）。"""
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT q.id, COALESCE(t.content, '') as text, q.answer, q.img
        FROM questions q
        LEFT JOIN translations t ON q.id = t.question_id AND t.lang = 'it' AND t.type = 'q'
        ORDER BY CAST(q.id AS INTEGER) ASC
    """)
    rows = cursor.fetchall()
    conn.close()
    return [
        (qid, text, bool(answer), img if img else None)
        for (qid, text, answer, img) in rows
    ]


def scan_incomplete_question_rows() -> List[Tuple[str, str, bool, Optional[str]]]:
    """
    掃描全庫：依 _get_missing_target_languages 判斷是否尚有缺語言、無效 JSON，
    或任一語種解析含舊模板標記（如「【」）需翻新者。用於 failed_ids.txt 為空時補洞。
    """
    conn = get_db_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT q.id, COALESCE(t.content, '') as text, q.answer, q.img
            FROM questions q
            LEFT JOIN translations t ON q.id = t.question_id AND t.lang = 'it' AND t.type = 'q'
            ORDER BY CAST(q.id AS INTEGER) ASC
            """
        )
        all_rows = [
            (qid, text, bool(answer), img if img else None)
            for (qid, text, answer, img) in cursor.fetchall()
        ]
        total = len(all_rows)
        incomplete: List[Tuple[str, str, bool, Optional[str]]] = []
        for i, row in enumerate(all_rows):
            if total >= 500 and (i + 1) % 500 == 0:
                print(f"   … 掃描進度 {i + 1}/{total} 題")
            qid = str(row[0])
            if _get_missing_target_languages(conn, qid):
                incomplete.append(row)
        print(f"🔍 掃描完成：共 {len(incomplete)}/{total} 題需要補全或翻新解析。")
        return incomplete
    finally:
        conn.close()


def get_structured_progress_counts() -> Tuple[int, int, int]:
    """
    啟動前統計：
    - 按要求先執行 count(*) 查詢（type='e' 且 content 像 JSON）
    - 再估算「按題目」已完成數與剩餘數
    返回: (structured_rows, completed_questions, remaining_questions)
    """
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        # 用戶要求的固定查詢（保留原樣）
        cursor.execute("SELECT count(*) FROM translations WHERE type='e' AND content LIKE '{%'")
        structured_rows = int(cursor.fetchone()[0] or 0)

        cursor.execute("SELECT count(*) FROM questions")
        total_questions = int(cursor.fetchone()[0] or 0)

        cursor.execute("SELECT count(DISTINCT question_id) FROM translations WHERE type='e' AND content LIKE '{%'")
        completed_questions = int(cursor.fetchone()[0] or 0)

        remaining_questions = max(0, total_questions - completed_questions)
        return structured_rows, completed_questions, remaining_questions
    finally:
        conn.close()


def _try_fix_json(text: str) -> Optional[str]:
    """
    尝试修复损坏的 JSON（强力清洗 + 简单修复）
    返回修复后的 JSON 字符串，如果无法修复则返回 None
    """
    fixed = str(text or "").strip()
    if not fixed:
        return None

    # 1) 清理 Markdown 代码块（```json ... ``` / ``` ... ```）
    fixed = re.sub(r"^\s*```(?:json)?\s*", "", fixed, flags=re.IGNORECASE)
    fixed = re.sub(r"\s*```\s*$", "", fixed)
    fixed = fixed.strip()

    # 2) 移除非法控制字符（保留常用可见字符与换行）
    fixed = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", fixed)

    # 3) 截取最外层 JSON 对象
    start_idx = fixed.find("{")
    end_idx = fixed.rfind("}")
    if start_idx >= 0 and end_idx > start_idx:
        fixed = fixed[start_idx : end_idx + 1]

    # 4) 若出现 Python 风格布尔/null，尝试转成 JSON
    fixed = re.sub(r"\bTrue\b", "true", fixed)
    fixed = re.sub(r"\bFalse\b", "false", fixed)
    fixed = re.sub(r"\bNone\b", "null", fixed)

    # 5) 如果 JSON 以 { 开头但没有以 } 结尾，尝试补齐
    if fixed.startswith("{") and not fixed.endswith("}"):
        last_brace = fixed.rfind("}")
        if last_brace > 0:
            fixed = fixed[:last_brace + 1]

    return fixed if fixed else None


def _try_parse_json_object(raw_text: str) -> Dict[str, object]:
    """
    容错 JSON 解析：
    - 优先直接解析
    - 失败后尝试把单引号改成双引号再解析
    """
    cleaned = _try_fix_json(raw_text)
    if not cleaned:
        raise ValueError("响应为空或清洗后为空")

    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError:
        single_quote_fixed = cleaned.replace("'", '"')
        parsed = json.loads(single_quote_fixed)

    if not isinstance(parsed, dict):
        raise ValueError("返回内容不是 JSON object")
    return parsed


def _normalize_key_points(raw_key_points: object) -> Optional[List[Dict[str, str]]]:
    """
    盡力把 key_points 修正為:
    [{"title":"...","content":"..."}, {"title":"...","content":"..."}]
    """
    kp = raw_key_points
    if isinstance(kp, str):
        text = kp.strip()
        if text:
            try:
                kp = json.loads(text)
            except Exception:
                maybe = _try_fix_json(text)
                if maybe:
                    try:
                        kp = json.loads(maybe.replace("'", '"'))
                    except Exception:
                        return None
                else:
                    return None
        else:
            return None

    if isinstance(kp, dict):
        kp = [kp]
    if not isinstance(kp, list) or not kp:
        return None

    normalized: List[Dict[str, str]] = []
    for item in kp:
        if isinstance(item, dict):
            normalized.append(
                {
                    "title": str(item.get("title", "")).strip(),
                    "content": str(item.get("content", "")).strip(),
                }
            )
        elif isinstance(item, str):
            normalized.append({"title": "", "content": item.strip()})

    normalized = [x for x in normalized if x["title"] or x["content"]]
    if not normalized:
        return None
    if len(normalized) == 1:
        normalized.append({"title": "核心提醒", "content": normalized[0]["content"]})
    return normalized[:2]


def _validate_explanations_for_langs(
    result: Dict[str, object], langs: List[str]
) -> Dict[str, Dict]:
    """校驗 API 返回 JSON 中指定語言區塊。"""
    validated_result: Dict[str, Dict] = {}
    for lang in langs:
        if lang not in result:
            print(f"⚠️  警告：缺少语言 {lang} 的解析，跳过")
            continue

        lang_data = result[lang]
        if not isinstance(lang_data, dict):
            print(f"⚠️  警告：语言 {lang} 的数据格式不正确，跳过")
            continue

        valid_lang_data: Dict[str, object] = {}

        if "detailed_description" in lang_data:
            valid_lang_data["detailed_description"] = str(lang_data["detailed_description"])
        else:
            print(f"⚠️  警告：语言 {lang} 缺少 detailed_description，跳过")
            continue

        if "key_points" in lang_data:
            normalized_key_points = _normalize_key_points(lang_data["key_points"])
            if normalized_key_points is None:
                print(f"⚠️  警告：语言 {lang} 的 key_points 无法自动修复，跳过")
                continue
            valid_lang_data["key_points"] = normalized_key_points
        else:
            print(f"⚠️  警告：语言 {lang} 缺少 key_points，跳过")
            continue

        if "study_tip" in lang_data:
            valid_lang_data["study_tip"] = str(lang_data["study_tip"])
        else:
            print(f"⚠️  警告：语言 {lang} 缺少 study_tip，跳过")
            continue

        validated_result[lang] = valid_lang_data  # type: ignore[assignment]

    if len(validated_result) != len(langs):
        raise ValueError(
            f"本組語言驗證不完整：需要 {langs}，實際得到 {list(validated_result.keys())}"
        )
    return validated_result  # type: ignore[return-value]


def generate_explanations_subset(
    question_text: str,
    answer: bool,
    langs: List[str],
    system_prompt: str,
    img_name: Optional[str] = None,
) -> Dict[str, Dict]:
    """
    單次 API：生成指定語言組（A 或 B）；若有配圖則多模態傳圖。
    """
    if not GEMINI_API_KEY:
        raise ValueError("未设置环境变量 GEMINI_API_KEY")
    if model is None:
        raise ValueError("GenerativeModel 未初始化，请检查 GEMINI_API_KEY")

    answer_text = "Vero" if answer else "Falso"
    lang_csv = ",".join(langs)
    img_display = img_name if img_name else "（無）"
    vision_block = (
        f"題目配圖檔名 img_name：{img_display}\n"
        "【看圖說話——必做】下筆前先核對配圖（若有）。若題幹與圖片明顯不符，一律以圖片為準；"
        "絕不可幻覺：圖中是農用車/拖拉機，就不能寫成停車讓行牌之類圖裡沒有的東西。\n"
        "若本請求未附像素圖，則僅依題幹判斷。\n\n"
    )
    user_prompt = (
        f"{vision_block}"
        f"題目（義大利語原文）：{question_text}\n"
        f"標準答案：{answer_text}\n"
        f"目標語言：{lang_csv}\n"
        "任務：僅返回上述語言鍵的 JSON 物件，不要輸出其它語言鍵。"
        "只寫判題邏輯與教練私房話，不要重複抄寫題幹。"
        "study_tip / detailed_description 等字串內引用題幹時請用「」直角引號，勿在字串中夾未轉義的英文 \" 。"
    )
    full_text = f"{system_prompt}\n\n{user_prompt}"
    response_text = ""

    img_path = _resolve_question_image_path(img_name)
    pil_img = None
    if img_path is not None and PILImage is not None:
        try:
            pil_img = PILImage.open(img_path).convert("RGB")
        except OSError as e:
            print(f"⚠️  無法載入配圖 {img_path}: {e}")
            pil_img = None
    elif img_path is not None and PILImage is None:
        print("⚠️  未安裝 Pillow，無法傳圖；請執行: pip3 install pillow")

    # 要求模型輸出合法 JSON，避免 study_tip 內未轉義 " 造成整段解析失敗
    json_gen_cfg = genai.GenerationConfig(response_mime_type="application/json")

    def _call_gemini(use_json_mime: bool):
        kwargs: Dict[str, object] = {}
        if use_json_mime:
            kwargs["generation_config"] = json_gen_cfg
        if pil_img is not None:
            return model.generate_content([full_text, pil_img], **kwargs)
        return model.generate_content(full_text, **kwargs)

    try:
        try:
            response = _call_gemini(True)
        except Exception as gen_exc:
            err_l = str(gen_exc).lower()
            if any(
                x in err_l
                for x in (
                    "response_mime_type",
                    "mime type",
                    "mimetype",
                    "unsupported",
                    "invalid argument",
                    "schema",
                )
            ):
                print(f"⚠️  JSON MIME 模式不可用，降級為一般生成: {gen_exc}")
                response = _call_gemini(False)
            else:
                raise
        response_text = (response.text or "").strip()

        result = _try_parse_json_object(response_text)

        validated = _validate_explanations_for_langs(result, langs)
        return validated

    except json.JSONDecodeError as e:
        print(f"❌ JSON 解析错误: {e}")
        print(f"响应内容（前500字符）: {response_text[:500]}")
        raise
    except Exception as e:
        if _is_model_not_found_error(e) and _switch_to_next_model_candidate():
            return generate_explanations_subset(
                question_text, answer, langs, system_prompt, img_name
            )
        print(f"❌ API 调用错误: {e}")
        raise


def _gemini_subset_with_429_backoff(
    conn: sqlite3.Connection,
    question_id: str,
    question_text: str,
    answer: bool,
    langs: List[str],
    system_prompt: str,
    group_label: str,
    img_name: Optional[str] = None,
) -> Tuple[Optional[Dict[str, Dict]], sqlite3.Connection]:
    """單組 API 呼叫 + 429 指數退避（首輪 90s，之後 180,360,...）。"""
    global failed_ids
    backoff_round = 0
    while True:
        try:
            return (
                generate_explanations_subset(
                    question_text, answer, langs, system_prompt, img_name
                ),
                conn,
            )
        except Exception as e:
            if not _is_resource_exhausted_error(e):
                raise
            backoff_round += 1
            if backoff_round > MAX_429_RECOVERY_ROUNDS:
                if question_id not in failed_ids:
                    failed_ids.append(question_id)
                print(
                    f"   ❌ ID {question_id} 组{group_label} 在 {MAX_429_RECOVERY_ROUNDS} 次 429 退避後仍失敗，"
                    f"已記錄至 failed_ids，跳過本題。"
                )
                return None, conn
            wait_sec = 60 * (2 ** (backoff_round - 1))
            print(
                f"   [重试中 {backoff_round}/{MAX_429_RECOVERY_ROUNDS}] "
                f"ID: {question_id} 组{group_label} 正在冷却 {wait_sec} 秒..."
            )
            conn = _ensure_db_alive(conn)
            time.sleep(wait_sec)
            conn = _ensure_db_alive(conn)
            continue


def generate_explanations_with_429_backoff(
    conn: sqlite3.Connection,
    question_id: str,
    question_text: str,
    answer: bool,
    langs_to_generate: List[str],
    img_name: Optional[str] = None,
) -> Tuple[Optional[Dict[str, Dict]], sqlite3.Connection]:
    """
    每題按 A/B 兩組請求；任一組耗盡退避則整題標記失敗並寫入 failed_ids。
    """
    target_set = set(langs_to_generate)
    group_a = [lang for lang in LANG_GROUP_A if lang in target_set]
    group_b = [lang for lang in LANG_GROUP_B if lang in target_set]

    explanations: Dict[str, Dict] = {}
    if group_a:
        part_a, conn = _gemini_subset_with_429_backoff(
            conn,
            question_id,
            question_text,
            answer,
            group_a,
            SYSTEM_PROMPT_GROUP_A,
            "A",
            img_name,
        )
        if part_a is None:
            return None, conn
        explanations.update(part_a)

    if group_a and group_b:
        print(f"   ⏸️  A 组完成，等待 {INTER_GROUP_SLEEP_SEC} 秒后请求 B 组...")
        time.sleep(INTER_GROUP_SLEEP_SEC)

    if group_b:
        part_b, conn = _gemini_subset_with_429_backoff(
            conn,
            question_id,
            question_text,
            answer,
            group_b,
            SYSTEM_PROMPT_GROUP_B,
            "B",
            img_name,
        )
        if part_b is None:
            return None, conn
        explanations.update(part_b)

    if set(explanations.keys()) != target_set:
        raise ValueError(
            f"语言键异常：期望 {langs_to_generate}，得到 {list(explanations.keys())}"
        )
    return explanations, conn


def save_explanations_to_db(question_id: str, explanations: Dict[str, Dict], conn: sqlite3.Connection):
    """
    将解析保存到数据库（每次处理后立即提交，防止 Token 浪费）
    """
    cursor = conn.cursor()

    for lang, lang_data in explanations.items():
        if lang not in TARGET_LANGUAGES:
            continue

        # 将结构化数据转换为紧凑型 JSON 字符串（无空格，节省存储）
        content_json = json.dumps(lang_data, ensure_ascii=False, separators=(',', ':'))

        # 检查是否已存在
        cursor.execute("""
            SELECT question_id FROM translations
            WHERE question_id = ? AND lang = ? AND type = 'e'
        """, (question_id, lang))

        existing = cursor.fetchone()

        if existing:
            # 更新现有记录（覆盖旧格式）
            cursor.execute("""
                UPDATE translations
                SET content = ?
                WHERE question_id = ? AND lang = ? AND type = 'e'
            """, (content_json, question_id, lang))
        else:
            # 插入新记录
            cursor.execute("""
                INSERT INTO translations (question_id, lang, type, content)
                VALUES (?, ?, 'e', ?)
            """, (question_id, lang, content_json))

    # 提交動作由外層批次控制（例如每處理 20 題統一 commit）


def process_batch(
    conn: sqlite3.Connection,
    missing_questions: List[Tuple[str, str, bool, Optional[str]]],
    start_idx: int,
    batch_limit: Optional[int] = None,
) -> Tuple[int, int, int, int, sqlite3.Connection]:
    """
    处理一批题目
    返回: (成功数, 失败数, 处理数, 跳過數, conn)（長時間 429 退避後 conn 可能被替換）
    """
    if batch_limit is not None:
        end_idx = min(start_idx + batch_limit, len(missing_questions))
        batch_questions = missing_questions[start_idx:end_idx]
    else:
        batch_questions = missing_questions[start_idx:]
        end_idx = len(missing_questions)

    total_count = len(missing_questions)
    success_count = 0
    error_count = 0
    processed_count = 0
    skipped_count = 0
    since_last_commit = 0
    global _consecutive_final_429_failures

    try:
        for idx, (question_id, question_text, answer, img_name) in enumerate(
            batch_questions
        ):
            current_idx = start_idx + idx + 1
            processed_count += 1

            try:
                if RUN_OPTIONS.get("force"):
                    langs_to_generate = TARGET_LANGUAGES[:]
                else:
                    # 断点续传：只补齐缺失语言，不重刷已完成语言
                    langs_to_generate = _get_missing_target_languages(conn, question_id)
                    if not langs_to_generate:
                        skipped_count += 1
                        print(".", end="", flush=True)
                        continue

                # 生成解析（逐語言調用；每語言含 429 指數退避）
                print(f"\n[进度: {current_idx}/{total_count}] 正在处理 ID: {question_id}...")
                print(f"   题目预览: {question_text[:60]}{'...' if len(question_text) > 60 else ''}")
                print(f"   标准答案: {'Vero' if answer else 'Falso'}")
                print(f"   🤖 正在调用 Gemini API... 待补语言: {','.join(langs_to_generate)}")
                explanations, conn = generate_explanations_with_429_backoff(
                    conn,
                    question_id,
                    question_text,
                    answer,
                    langs_to_generate,
                    img_name,
                )
                if explanations is None:
                    error_count += 1
                    _consecutive_final_429_failures += 1
                    print("   ⏭️  本題已標記為最終失敗，繼續下一題...")
                    if _consecutive_final_429_failures >= CIRCUIT_BREAKER_CONSECUTIVE_429_FAILURES:
                        raise CircuitBreakerTriggered(
                            "连续 3 道题在 429 退避耗尽后仍失败，触发熔断安全退出。"
                        )
                    continue
                _consecutive_final_429_failures = 0

                # 保存到数据库
                print("   💾 正在保存到数据库...")
                save_explanations_to_db(question_id, explanations, conn)
                zh_tip = ""
                zh_data = explanations.get("zh")
                if isinstance(zh_data, dict):
                    zh_tip = str(zh_data.get("study_tip", "")).strip()
                if zh_tip:
                    print("   🧠 zh.study_tip:")
                    print(zh_tip)

                success_count += 1
                since_last_commit += 1
                print(f"   ✅ 成功！已生成 {len(explanations)} 种语言的解析")

                # 每處理 10 題統一提交一次，減少磁碟 IO 並提升安全性
                if since_last_commit >= 10:
                    conn.commit()
                    since_last_commit = 0
                    print("   💾 已批量提交最近 10 題的解析變更。")

                # 成功處理一題後慢節奏（每題已含 2 次 API；15–20 秒隨機再請求下一題）
                if current_idx < total_count:
                    _sleep_post_question_success()

            except CircuitBreakerTriggered:
                raise
            except Exception as e:
                _consecutive_final_429_failures = 0
                error_count += 1
                print(f"   ❌ 错误: {e}")
                print(f"   ⏭️  跳过当前题目，继续处理下一题...")
                continue
    finally:
        # 即使异常退出（如 KeyboardInterrupt），也尽量落盘当前批次结果
        if since_last_commit > 0:
            conn.commit()
            print("   💾 检测到中断/异常，已提交本批未提交的解析变更。")
    print()
    return success_count, error_count, processed_count, skipped_count, conn


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="使用 Gemini 为 italy_quiz.db 生成多语言结构化解析（自然幽默教練口吻 · 可傳題圖）"
    )
    p.add_argument(
        "--only-wrong",
        action="store_true",
        help="只处理 user_progress 中 wrong_count>0 的题目（验证真人教練口吻模式）",
    )
    p.add_argument(
        "--force",
        action="store_true",
        help="忽略智能跳过，對排隊內每題六語全量重刷（非 force 時：缺語言／無效 JSON／任一語種含舊模板如「【」亦會觸發整題重刷）",
    )
    p.add_argument(
        "--limit",
        type=int,
        default=DEFAULT_RUN_LIMIT,
        metavar="N",
        help=(
            f"本次最多處理 N 道題；預設 {DEFAULT_RUN_LIMIT} 方便抽查語氣，"
            "傳 0 表示不限制（全庫）。全庫 --force 時務必傳 --limit 0。"
        ),
    )
    p.add_argument(
        "--start-id",
        type=int,
        default=None,
        metavar="QID",
        help="从指定 question_id（含）开始处理，例如 --start-id 1814",
    )
    p.add_argument(
        "--retry-failed",
        action="store_true",
        help=(
            "只處理專案根目錄 failed_ids.txt 中列出的題號（每行一個）。"
            "預設僅補齊缺失語言；若要整題重算請加 --force。"
        ),
    )
    p.add_argument(
        "--retry-incomplete",
        action="store_true",
        help=(
            "掃描資料庫，只處理解析不完整或需翻新的題（與斷點邏輯一致）。"
            "當 failed_ids.txt 為空、但曾因 DB 鎖等跳過題目時請用此項。"
        ),
    )
    return p.parse_args()


def main():
    """主函数（自动循环处理所有题目）"""
    args = parse_args()
    RUN_OPTIONS["only_wrong"] = bool(args.only_wrong)
    RUN_OPTIONS["force"] = bool(args.force)
    RUN_OPTIONS["limit"] = None if args.limit == 0 else args.limit
    RUN_OPTIONS["start_id"] = args.start_id
    RUN_OPTIONS["retry_failed"] = bool(args.retry_failed)
    RUN_OPTIONS["retry_incomplete"] = bool(args.retry_incomplete)

    if args.retry_failed and args.retry_incomplete:
        print("❌ 請勿同時使用 --retry-failed 與 --retry-incomplete，請擇一。")
        sys.exit(1)

    retry_failed_qids: List[str] = []
    if args.retry_failed:
        retry_failed_qids = _read_failed_ids_from_file()
        if not retry_failed_qids:
            print("❌ 無失敗題目可重試（failed_ids.txt 為空或不存在）。")
            print(
                "💡 若曾出現 database is locked 被跳過的題，failed_ids.txt 通常不會記錄；"
                "請改用：python3 ... --retry-incomplete"
            )
            sys.exit(0)
        if args.only_wrong:
            print("⚠️  已指定 --retry-failed，將忽略 --only-wrong，只依 failed_ids.txt 排隊。")
        print("💡 重試模式：預設僅補齊缺失語言；若要整題重算請加 --force")
    elif args.retry_incomplete:
        if args.only_wrong:
            print("⚠️  已指定 --retry-incomplete，將忽略 --only-wrong。")
        print("💡 不完整補洞模式：只處理掃描到的題目；預設不帶 --force 時僅補缺失語言。")

    if not GEMINI_API_KEY:
        print("❌ 未设置环境变量 GEMINI_API_KEY，无法调用 Gemini。")
        sys.exit(1)

    _reset_failed_ids_file()
    genai.configure(api_key=GEMINI_API_KEY)
    _setup_genai_model()
    print(f"🚦 当前模型候补序列: {', '.join(MODEL_CANDIDATES_PRIORITY)}")

    print("=" * 60)
    print("🚀 开始生成多语言结构化题目解析（自然教練口吻 · 可選配圖核對）")
    print("=" * 60)
    print(
        f"   only_wrong={RUN_OPTIONS['only_wrong']}  force={RUN_OPTIONS['force']}  "
        f"limit={RUN_OPTIONS.get('limit')}  start_id={RUN_OPTIONS.get('start_id')}  "
        f"retry_failed={RUN_OPTIONS.get('retry_failed')}  "
        f"retry_incomplete={RUN_OPTIONS.get('retry_incomplete')}"
    )
    print("=" * 60)
    print(f"📊 模型: {MODEL_NAME}")
    print(f"🌍 目标语言: {', '.join(TARGET_LANGUAGES)}")
    print(f"📦 批次大小: {BATCH_SIZE}")
    print(f"📋 批次限制: {'无限制（处理所有题目）' if BATCH_LIMIT is None else f'{BATCH_LIMIT} 题/次'}")
    print(
        f"⏱️  A/B 两组请求（组间 {INTER_GROUP_SLEEP_SEC} 秒），"
        f"每題完成後休息: {POST_SUCCESS_SLEEP_SEC_MIN:g}–{POST_SUCCESS_SLEEP_SEC_MAX:g} 秒（隨機）"
    )
    print("=" * 60)

    structured_rows, completed_questions, remaining_questions = get_structured_progress_counts()
    print(f"📌 结构化记录行数（type='e' 且 JSON）: {structured_rows}")
    print(f"📌 当前已完成结构化解析 {completed_questions} 道，剩余 {remaining_questions} 道，准备继续...")
    print("=" * 60)

    # 全局统计
    total_success = 0
    total_errors = 0
    total_processed = 0
    total_skipped = 0
    round_number = 0
    circuit_breaker_hit = False
    last_queue_total_for_golden = 0

    # 自动循环处理，直到所有题目完成
    while True:
        round_number += 1
        print(f"\n{'=' * 60}")
        print(f"🔄 第 {round_number} 轮处理")
        print(f"{'=' * 60}")

        # 获取待处理题目
        print("\n📋 正在检查数据库...")
        missing_questions = get_questions_with_missing_explanations()

        if RUN_OPTIONS.get("retry_incomplete"):
            print("\n📋 正在掃描資料庫（不完整 / 需翻新解析）…")
            missing_questions = scan_incomplete_question_rows()

        if RUN_OPTIONS.get("retry_failed"):
            by_id: Dict[str, Tuple[str, str, bool, Optional[str]]] = {
                str(q[0]): q for q in missing_questions
            }
            ordered_retry: List[Tuple[str, str, bool, Optional[str]]] = []
            for qid in retry_failed_qids:
                row = by_id.get(qid)
                if row is not None:
                    ordered_retry.append(row)
                else:
                    print(f"⚠️  failed_ids 中的 ID {qid} 不在題庫中，已跳过")
            missing_questions = ordered_retry

        start_id = RUN_OPTIONS.get("start_id")
        if isinstance(start_id, int) and start_id > 0:
            filtered_questions: List[Tuple[str, str, bool, Optional[str]]] = []
            for qid, text, answer, img_name in missing_questions:
                try:
                    if int(qid) >= start_id:
                        filtered_questions.append((qid, text, answer, img_name))
                except (TypeError, ValueError):
                    # 指定起始題號時，只處理可轉 int 的純數字題號
                    continue
            missing_questions = filtered_questions

        lim = RUN_OPTIONS.get("limit")
        if isinstance(lim, int) and lim > 0:
            missing_questions = missing_questions[:lim]

        total_count = len(missing_questions)

        if total_count == 0:
            if RUN_OPTIONS.get("only_wrong"):
                print("✅ 无 wrong_count>0 的题目，或缺少 user_progress 表。无需处理。")
            else:
                print("✅ 题目列表为空，无需处理！")
            break

        last_queue_total_for_golden = total_count

        # 应用批次限制（控制成本）
        if BATCH_LIMIT is not None and total_count > BATCH_LIMIT:
            print(f"⚠️  注意：待处理题目总数 ({total_count}) 超过批次限制 ({BATCH_LIMIT})")
            print(f"📦 本次运行将只处理前 {BATCH_LIMIT} 道题目")
            batch_limit = BATCH_LIMIT
        else:
            print(f"🚀 自动模式：将处理所有 {total_count} 道题目")
            batch_limit = None

        print(f"📊 待处理题目总数: {total_count}")
        print(f"💰 使用模型: {MODEL_NAME}")
        n = total_count if batch_limit is None else batch_limit
        # 粗估：A/B 兩次請求 + 組間等待 + 單題完成後等待
        avg_post_sleep = (
            POST_SUCCESS_SLEEP_SEC_MIN + POST_SUCCESS_SLEEP_SEC_MAX
        ) / 2.0 + POST_SUCCESS_DYNAMIC_BACKOFF_SEC
        estimated_minutes = n * (avg_post_sleep + INTER_GROUP_SLEEP_SEC) / 60
        estimated_hours = estimated_minutes / 60
        if estimated_hours >= 1:
            print(f"⏳ 预计处理时间: {estimated_hours:.1f} 小时 ({estimated_minutes:.1f} 分钟)")
        else:
            print(f"⏳ 预计处理时间: {estimated_minutes:.1f} 分钟")
        print("\n" + "=" * 60)

        # 连接数据库
        conn = get_db_connection()

        triggered_breaker = False
        try:
            # 分批处理
            start_idx = 0
            while start_idx < total_count:
                if batch_limit is not None and start_idx >= batch_limit:
                    break

                batch_num = start_idx // BATCH_SIZE + 1
                batch_end = min(start_idx + BATCH_SIZE, total_count)
                if batch_limit is not None:
                    batch_end = min(batch_end, start_idx + batch_limit)

                print(f"\n📦 处理批次 {batch_num} (题目 {start_idx + 1}-{batch_end}/{total_count})")

                success, errors, processed, skipped, conn = process_batch(
                    conn, missing_questions, start_idx, BATCH_SIZE
                )
                total_success += success
                total_errors += errors
                total_processed += processed
                total_skipped += skipped

                start_idx += BATCH_SIZE

                # 批次之间的额外延迟（與單題成功後節奏一致）
                if start_idx < total_count and (batch_limit is None or start_idx < batch_limit):
                    wait_sec = (
                        random.uniform(
                            POST_SUCCESS_SLEEP_SEC_MIN,
                            POST_SUCCESS_SLEEP_SEC_MAX,
                        )
                        + POST_SUCCESS_DYNAMIC_BACKOFF_SEC
                    )
                    print(f"\n⏸️  批次完成，等待 {wait_sec:.1f} 秒后继续...")
                    time.sleep(wait_sec)
        except CircuitBreakerTriggered as e:
            triggered_breaker = True
            circuit_breaker_hit = True
            print(f"\n🛑 熔断触发：{e}")
            print("🛡️ 为保护 API Key，本次任务将安全退出。")

        finally:
            # 再次兜底提交，避免外层异常导致最近变更丢失
            try:
                conn.commit()
            finally:
                conn.close()

        if triggered_breaker:
            break

        # 如果设置了批次限制，需要继续下一轮
        if BATCH_LIMIT is not None:
            remaining = get_questions_with_missing_explanations()
            if len(remaining) > 0:
                print(f"\n⏸️  本轮完成，还有 {len(remaining)} 道题目待处理")
                print("等待 5 秒后开始下一轮...")
                time.sleep(5)
                continue
            else:
                print("\n✅ 所有题目已处理完成！")
                break
        else:
            # 无限制模式，处理完所有题目后退出
            break

    _write_failed_ids_file()

    # 输出最终统计信息
    print("\n" + "=" * 60)
    print("📊 全部处理完成！")
    print("=" * 60)
    print(f"📂 掃過題數（排隊內）: {total_processed}")
    print(f"⏭️  已齊全跳過: {total_skipped} 題（未呼叫 API；若要重寫口吻請加 --force）")
    print(f"✅ API 成功: {total_success} 题")
    print(f"❌ 总失败: {total_errors} 题")
    api_attempts = total_success + total_errors
    if api_attempts > 0:
        print(f"📈 API 成功率: {total_success / api_attempts * 100:.1f}%")
    else:
        print("📈 無 API 呼叫（本輪題目皆已齊全或僅跳過）")
    print(f"🔄 总轮数: {round_number}")
    print("=" * 60)

    # --force 全隊列跑完且 API 失敗率低於 1% 時，標記金庫就緒（供日誌 / CI 檢索）
    denom = total_success + total_errors
    if (
        RUN_OPTIONS.get("force")
        and not circuit_breaker_hit
        and last_queue_total_for_golden > 0
        and total_processed == last_queue_total_for_golden
        and denom == total_processed
        and denom > 0
        and (total_errors / denom) < 0.01
    ):
        print("GOLDEN DATABASE READY", flush=True)


if __name__ == "__main__":
    main()
