#!/usr/bin/env python3
"""
监控关键词生成进度
"""

import sqlite3
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
DATABASE_PATH = PROJECT_ROOT / "assets" / "italy_quiz.db"

if not DATABASE_PATH.exists():
    raise SystemExit(f"❌ 数据库文件不存在: {DATABASE_PATH}")

def get_stats():
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()

    # 总数
    cursor.execute("SELECT COUNT(*) FROM questions")
    total = cursor.fetchone()[0]

    # 有数据的
    cursor.execute("""
        SELECT COUNT(*)
        FROM questions
        WHERE keywords_json IS NOT NULL
          AND keywords_json != ''
          AND keywords_json != '[]'
    """)
    has_keywords = cursor.fetchone()[0]

    # 缺失的
    missing = total - has_keywords

    # 覆盖率
    coverage = (has_keywords / total * 100) if total > 0 else 0

    conn.close()

    return total, has_keywords, missing, coverage

if __name__ == "__main__":
    print("=" * 60)
    print("📊 关键词生成进度监控")
    print("=" * 60)
    print("按 Ctrl+C 退出监控\n")

    last_count = 0

    try:
        while True:
            total, has_keywords, missing, coverage = get_stats()

            # 计算新增数量
            new_count = has_keywords - last_count
            if last_count > 0:
                print(f"⏱️  {time.strftime('%H:%M:%S')} | 新增: +{new_count} | 总计: {has_keywords}/{total} ({coverage:.2f}%) | 剩余: {missing}")
            else:
                print(f"⏱️  {time.strftime('%H:%M:%S')} | 总计: {has_keywords}/{total} ({coverage:.2f}%) | 剩余: {missing}")

            last_count = has_keywords

            if missing == 0:
                print("\n✅ 所有题目处理完成！")
                break

            time.sleep(10)  # 每10秒更新一次

    except KeyboardInterrupt:
        print("\n\n监控已停止")
