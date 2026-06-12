#!/usr/bin/env python3
"""
测试脚本：验证 keywords_json 写入功能
"""

import sqlite3
import json
import atexit
import shutil
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
SOURCE_DATABASE_PATH = PROJECT_ROOT / "assets" / "italy_quiz.db"

if not SOURCE_DATABASE_PATH.exists():
    raise SystemExit(f"❌ 数据库文件不存在: {SOURCE_DATABASE_PATH}")

tmp_dir = Path(tempfile.mkdtemp(prefix="patentego_keywords_test_"))
atexit.register(lambda: shutil.rmtree(tmp_dir, ignore_errors=True))
DATABASE_PATH = tmp_dir / "italy_quiz.test.db"
shutil.copy2(SOURCE_DATABASE_PATH, DATABASE_PATH)

print(f"🔍 数据库路径: {DATABASE_PATH}")
print(f"🔍 源数据库路径: {SOURCE_DATABASE_PATH}")
print("ℹ️  使用临时数据库副本测试，不会修改正式题库。")
print(f"🔍 数据库存在: {DATABASE_PATH.exists()}")

# 连接数据库
conn = sqlite3.connect(DATABASE_PATH)
cursor = conn.cursor()

# 测试数据
test_keywords = [
    {"it": "Carreggiata", "zh": "行车道"},
    {"it": "Banchina", "zh": "路肩"}
]

keywords_json = json.dumps(test_keywords, ensure_ascii=False)

print(f"\n🔍 测试 JSON: {keywords_json}")

# 查找第一个有数据的记录进行测试
print(f"\n📝 查找第一个有 keywords_json 的记录...")
cursor.execute("SELECT id, keywords_json FROM questions WHERE keywords_json IS NOT NULL AND keywords_json != '' LIMIT 1")
test_record = cursor.fetchone()
if test_record:
    test_id = test_record[0]
    print(f"   找到记录 ID: {test_id}")
    print(f"   当前 keywords_json: {test_record[1][:100]}...")

    # 更新这个记录
    print(f"\n📝 更新 id='{test_id}' 的记录...")
    cursor.execute("UPDATE questions SET keywords_json = ? WHERE id = ?", (keywords_json, test_id))
    conn.commit()

    # 验证更新
    cursor.execute("SELECT keywords_json FROM questions WHERE id = ?", (test_id,))
    new_value = cursor.fetchone()
    print(f"   更新后: {new_value[0] if new_value and new_value[0] else 'None'}")

    if new_value and new_value[0] == keywords_json:
        print("✅ 更新成功！")
    else:
        print("❌ 更新失败！")

    # 验证命令行查询
    print(f"\n🔍 使用命令行验证...")
    import subprocess
    result = subprocess.run(
        ["sqlite3", str(DATABASE_PATH), f"SELECT keywords_json FROM questions WHERE id='{test_id}' LIMIT 1;"],
        capture_output=True,
        text=True
    )
    print(f"   命令行输出: {result.stdout.strip()}")
else:
    print("❌ 没有找到有 keywords_json 的记录")

# 查找第一个没有数据的记录进行测试
print(f"\n📝 查找第一个没有 keywords_json 的记录...")
cursor.execute("SELECT id FROM questions WHERE keywords_json IS NULL OR keywords_json = '' LIMIT 1")
empty_record = cursor.fetchone()
if empty_record:
    empty_id = empty_record[0]
    print(f"   找到记录 ID: {empty_id}")

    # 更新这个记录
    print(f"\n📝 更新 id='{empty_id}' 的记录...")
    cursor.execute("UPDATE questions SET keywords_json = ? WHERE id = ?", (keywords_json, empty_id))
    conn.commit()

    # 验证更新
    cursor.execute("SELECT keywords_json FROM questions WHERE id = ?", (empty_id,))
    new_value = cursor.fetchone()
    print(f"   更新后: {new_value[0] if new_value and new_value[0] else 'None'}")

    if new_value and new_value[0] == keywords_json:
        print("✅ 更新成功！")

        # 验证命令行查询
        print(f"\n🔍 使用命令行验证...")
        import subprocess
        result = subprocess.run(
            ["sqlite3", str(DATABASE_PATH), f"SELECT keywords_json FROM questions WHERE id='{empty_id}' LIMIT 1;"],
            capture_output=True,
            text=True
        )
        print(f"   命令行输出: {result.stdout.strip()}")
    else:
        print("❌ 更新失败！")
else:
    print("❌ 没有找到空的记录")

conn.close()
