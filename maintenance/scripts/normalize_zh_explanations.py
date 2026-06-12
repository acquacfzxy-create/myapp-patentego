#!/usr/bin/env python3
"""
清理 translations 表中 lang='zh'、type='e' 的解析：
1) 繁體轉簡體（OpenCC t2s）
2) 替換程式黑話（toBeTruthy/true/false/null 等）
3) 語氣柔化（懂？明白嗎？等）
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Tuple

try:
    from opencc import OpenCC  # type: ignore
except Exception:
    OpenCC = None  # type: ignore[misc, assignment]


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
DATABASE_PATH = PROJECT_ROOT / "assets" / "italy_quiz.db"


CODE_WORD_PATTERNS: List[Tuple[re.Pattern[str], str]] = [
    (re.compile(r"`?\btoBeTruthy\b`?", flags=re.IGNORECASE), "正确"),
    (re.compile(r"`?\btoBeFalsy\b`?", flags=re.IGNORECASE), "错误"),
    (re.compile(r"`?\btrue\b`?", flags=re.IGNORECASE), "正确"),
    (re.compile(r"`?\bfalse\b`?", flags=re.IGNORECASE), "错误"),
    (re.compile(r"`?\bnull\b`?", flags=re.IGNORECASE), "没有内容"),
]

TONE_SOFTEN_PATTERNS: List[Tuple[re.Pattern[str], str]] = [
    (re.compile(r"[，, ]*懂[吗嗎]\??", flags=re.IGNORECASE), "。记住这一点对考试很有帮助。"),
    (re.compile(r"[，, ]*明白[吗嗎]\??", flags=re.IGNORECASE), "。记住这一点对考试很有帮助。"),
    (re.compile(r"[，, ]*懂\??", flags=re.IGNORECASE), "。记住这一点对考试很有帮助。"),
]


def _to_simplified(text: str, cc: Any) -> str:
    if not text:
        return text
    if cc is None:
        return text
    return str(cc.convert(text))


def _normalize_text(text: str, cc: Any) -> str:
    out = _to_simplified(text, cc)
    for pattern, repl in CODE_WORD_PATTERNS:
        out = pattern.sub(repl, out)
    for pattern, repl in TONE_SOFTEN_PATTERNS:
        out = pattern.sub(repl, out)
    out = re.sub(r"记住这一点对考试很有帮助。{2,}", "记住这一点对考试很有帮助。", out)
    out = re.sub(r"([。！？])\1+", r"\1", out)
    return out.strip()


def _normalize_json_obj(obj: Any, cc: Any) -> Any:
    if isinstance(obj, str):
        return _normalize_text(obj, cc)
    if isinstance(obj, list):
        return [_normalize_json_obj(x, cc) for x in obj]
    if isinstance(obj, dict):
        out: Dict[str, Any] = {}
        for k, v in obj.items():
            out[k] = _normalize_json_obj(v, cc)
        return out
    return obj


def run(apply_changes: bool, limit: int | None) -> None:
    if not DATABASE_PATH.exists():
        raise FileNotFoundError(f"数据库文件不存在: {DATABASE_PATH}")

    cc = OpenCC("t2s") if OpenCC is not None else None
    if cc is None:
        print("⚠️ 未检测到 opencc，将跳过繁转简，仅执行术语与语气清理。")
        print("   可安装: pip3 install opencc-python-reimplemented")

    conn = sqlite3.connect(str(DATABASE_PATH), timeout=120.0)
    cur = conn.cursor()

    sql = """
        SELECT rowid, question_id, content
        FROM translations
        WHERE lang='zh' AND type='e' AND content LIKE '{%'
        ORDER BY CAST(question_id AS INTEGER)
    """
    if limit is not None and limit > 0:
        sql += " LIMIT ?"
        cur.execute(sql, (limit,))
    else:
        cur.execute(sql)
    rows = cur.fetchall()

    changed = 0
    skipped = 0
    parse_failed = 0
    for rowid, qid, content in rows:
        raw = str(content or "").strip()
        if not raw:
            skipped += 1
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError:
            parse_failed += 1
            continue

        normalized_obj = _normalize_json_obj(obj, cc)
        normalized = json.dumps(normalized_obj, ensure_ascii=False, separators=(",", ":"))
        if normalized == raw:
            skipped += 1
            continue

        changed += 1
        if apply_changes:
            cur.execute(
                "UPDATE translations SET content=? WHERE rowid=?",
                (normalized, rowid),
            )
        if changed <= 5:
            print(f"🧩 已规范化 question_id={qid}")

    if apply_changes:
        conn.commit()
    conn.close()

    mode = "写入" if apply_changes else "预览"
    print("\n==============================")
    print(f"✅ {mode}完成")
    print(f"总记录: {len(rows)}")
    print(f"已变更: {changed}")
    print(f"无变化: {skipped}")
    print(f"JSON解析失败: {parse_failed}")
    print("==============================")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="清理中文解析：繁转简 + 黑话替换 + 语气修正")
    p.add_argument("--dry-run", action="store_true", help="只预览统计，不写入数据库")
    p.add_argument("--limit", type=int, default=None, help="最多处理 N 条记录")
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run(apply_changes=not args.dry_run, limit=args.limit)
