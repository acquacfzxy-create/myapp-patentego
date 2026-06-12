#!/usr/bin/env python3
"""
检查 italy_quiz.db 数据库中 keywords_json 的覆盖率
"""

import sqlite3
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
DATABASE_PATH = PROJECT_ROOT / "assets" / "italy_quiz.db"

if not DATABASE_PATH.exists():
    raise SystemExit(f"❌ 数据库文件不存在: {DATABASE_PATH}")

print("=" * 60)
print("📊 数据库关键词覆盖率统计")
print("=" * 60)

# 连接数据库
conn = sqlite3.connect(DATABASE_PATH)
cursor = conn.cursor()

# 1. 统计总数
cursor.execute("SELECT COUNT(*) FROM questions")
total = cursor.fetchone()[0]
print(f"\n1️⃣  总题目数: {total}")

# 2. 统计缺失
cursor.execute("""
    SELECT COUNT(*)
    FROM questions
    WHERE keywords_json IS NULL
       OR keywords_json = ''
       OR keywords_json = '[]'
""")
missing = cursor.fetchone()[0]
print(f"2️⃣  缺失关键词的题目数: {missing}")

# 3. 统计有数据的
cursor.execute("""
    SELECT COUNT(*)
    FROM questions
    WHERE keywords_json IS NOT NULL
      AND keywords_json != ''
      AND keywords_json != '[]'
""")
has_keywords = cursor.fetchone()[0]
print(f"3️⃣  有关键词的题目数: {has_keywords}")

# 4. 计算比例
if total > 0:
    missing_percentage = (missing / total) * 100
    coverage_percentage = (has_keywords / total) * 100
    print(f"\n📈 覆盖率统计:")
    print(f"   - 缺失比例: {missing_percentage:.2f}%")
    print(f"   - 覆盖率: {coverage_percentage:.2f}%")
else:
    print("\n⚠️  警告：数据库中没有题目")

# 5. 列举样例（前 5 个）
print(f"\n4️⃣  前 5 个缺失关键词的题目样例（按 ID 升序）:")
print("-" * 60)
cursor.execute("""
    SELECT q.id, t.content as question_text
    FROM questions q
    LEFT JOIN translations t ON q.id = t.question_id
        AND t.lang = 'it'
        AND t.type = 'q'
    WHERE (q.keywords_json IS NULL
           OR q.keywords_json = ''
           OR q.keywords_json = '[]')
      AND t.content IS NOT NULL
    ORDER BY CAST(q.id AS INTEGER)
    LIMIT 5
""")

samples = cursor.fetchall()
if samples:
    for idx, (question_id, question_text) in enumerate(samples, 1):
        print(f"\n   题目 #{idx}:")
        print(f"   ID: {question_id}")
        if question_text:
            # 如果题目太长，截取前 120 个字符
            display_text = question_text[:120] + "..." if len(question_text) > 120 else question_text
            print(f"   意语正文: {display_text}")
        else:
            print(f"   意语正文: (无翻译)")
else:
    print("   (没有找到缺失关键词的题目)")

# 6. 列举样例（后 5 个）
print(f"\n5️⃣  后 5 个缺失关键词的题目样例（按 ID 降序）:")
print("-" * 60)
cursor.execute("""
    SELECT q.id, t.content as question_text
    FROM questions q
    LEFT JOIN translations t ON q.id = t.question_id
        AND t.lang = 'it'
        AND t.type = 'q'
    WHERE (q.keywords_json IS NULL
           OR q.keywords_json = ''
           OR q.keywords_json = '[]')
      AND t.content IS NOT NULL
    ORDER BY CAST(q.id AS INTEGER) DESC
    LIMIT 5
""")

samples_end = cursor.fetchall()
if samples_end:
    for idx, (question_id, question_text) in enumerate(samples_end, 1):
        print(f"\n   题目 #{idx}:")
        print(f"   ID: {question_id}")
        if question_text:
            display_text = question_text[:120] + "..." if len(question_text) > 120 else question_text
            print(f"   意语正文: {display_text}")
        else:
            print(f"   意语正文: (无翻译)")

# 7. 检查 ID 1-10 的状态
print(f"\n6️⃣  检查 ID 1-10 的关键词状态:")
print("-" * 60)
cursor.execute("""
    SELECT q.id,
           CASE
               WHEN q.keywords_json IS NULL OR q.keywords_json = '' OR q.keywords_json = '[]'
               THEN '缺失'
               ELSE '有数据'
           END as status,
           LENGTH(q.keywords_json) as json_length
    FROM questions q
    WHERE CAST(q.id AS INTEGER) BETWEEN 1 AND 10
    ORDER BY CAST(q.id AS INTEGER)
""")

id_status = cursor.fetchall()
for question_id, status, json_length in id_status:
    print(f"   ID {question_id}: {status}" + (f" (JSON 长度: {json_length})" if json_length else ""))

print("\n" + "=" * 60)
print("✅ 统计完成")
print("=" * 60)

conn.close()
