#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
重新分配数据库题目的章节编号
根据原始 JSON 文件中的嵌套结构，将 JSON 的顶级 Key（章节名）映射到数据库的 chapter 字段（1-25）
"""

import json
import sqlite3
import os
import sys
from typing import Dict, List, Optional
from difflib import SequenceMatcher

# ============================================================================
# 配置区域
# ============================================================================

# JSON 文件路径
JSON_FILE_PATHS = [
    '/Users/fabio/Desktop/patente/quizPatenteB2023.json',
    './quizPatenteB2023.json',
    '../patente/quizPatenteB2023.json',
]

# 数据库路径
DB_PATH = 'assets/italy_quiz.db'

# JSON 顶级键（章节名）到章节编号（1-25）的映射
# 注意：这个映射需要根据实际的 JSON 文件来填写
# 下面是示例结构，实际需要根据 JSON 文件中的键名来填写
CHAPTER_MAPPING = {
    # 章节编号从 1 开始，映射到 JSON 中的顶级键名
    # 示例：
    # 'definizioni-generali-doveri-strada': 1,
    # 'segnali-pericolo': 2,
    # ... 需要根据实际 JSON 文件填写完整的 25 个映射
}


def find_json_file() -> Optional[str]:
    """查找 JSON 文件"""
    for path in JSON_FILE_PATHS:
        if os.path.exists(path):
            return path
    return None


def extract_chapter_keys_from_json(json_path: str) -> List[str]:
    """从 JSON 文件中提取所有顶级键（章节名）"""
    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        return list(data.keys())
    except Exception as e:
        print(f"❌ 读取 JSON 文件失败: {e}")
        return []


def build_chapter_mapping(json_path: str) -> Dict[str, int]:
    """
    构建章节映射表
    根据 JSON 文件的顶级键顺序，自动创建 1-25 的映射
    """
    keys = extract_chapter_keys_from_json(json_path)
    if not keys:
        return {}
    
    mapping = {}
    for idx, key in enumerate(keys, start=1):
        if idx <= 25:  # 只映射前 25 个章节
            mapping[key] = idx
    
    return mapping


def normalize_text(text: str) -> str:
    """标准化文本用于匹配（去除空格、转换为小写等）"""
    if not text:
        return ""
    # 转换为小写，去除首尾空格，标准化空白字符
    text = text.lower().strip()
    # 将多个空白字符替换为单个空格
    import re
    text = re.sub(r'\s+', ' ', text)
    return text


def find_question_by_content(db: sqlite3.Connection, question_text: str, lang: str = 'it', threshold: float = 0.85) -> Optional[str]:
    """
    根据题目内容在数据库中查找题目 ID
    使用文本相似度匹配，因为 JSON 中的文本和数据库中的文本可能略有差异
    
    Args:
        db: 数据库连接
        question_text: 题目文本
        lang: 语言代码（默认 'it'）
        threshold: 相似度阈值（0-1，默认 0.85）
    
    Returns:
        匹配的题目 ID，如果未找到则返回 None
    """
    normalized_query = normalize_text(question_text)
    if not normalized_query:
        return None
    
    cursor = db.cursor()
    
    # 查询意大利语题目
    cursor.execute('''
        SELECT q.id, t.content
        FROM questions q
        JOIN translations t ON q.id = t.question_id
        WHERE t.lang = ? AND t.type = 'q'
    ''', (lang,))
    
    results = cursor.fetchall()
    
    best_match_id = None
    best_similarity = 0.0
    
    # 精确匹配（标准化后）
    for question_id, content in results:
        normalized_content = normalize_text(content)
        if normalized_content == normalized_query:
            return question_id  # 完全匹配，直接返回
        
        # 计算相似度
        similarity = SequenceMatcher(None, normalized_query, normalized_content).ratio()
        if similarity > best_similarity:
            best_similarity = similarity
            best_match_id = question_id
    
    # 如果最佳相似度超过阈值，返回匹配的 ID
    if best_similarity >= threshold:
        return best_match_id
    
    return None


def update_question_chapter(db: sqlite3.Connection, question_id: str, chapter_id: int) -> bool:
    """更新题目的章节编号"""
    try:
        cursor = db.cursor()
        cursor.execute('UPDATE questions SET chapter = ? WHERE id = ?', (chapter_id, question_id))
        db.commit()
        return cursor.rowcount > 0
    except Exception as e:
        print(f"⚠️ 更新题目 {question_id} 失败: {e}")
        return False


def extract_questions_from_json_chapter(chapter_data: dict) -> List[dict]:
    """从 JSON 章节数据中提取所有题目"""
    questions = []
    
    if not isinstance(chapter_data, dict):
        return questions
    
    # 遍历所有子键
    for sub_key, sub_value in chapter_data.items():
        if isinstance(sub_value, list):
            # 如果值是列表，遍历列表中的每个元素
            for item in sub_value:
                if isinstance(item, dict):
                    # 检查是否包含题目字段（通常是 'q'）
                    if 'q' in item:
                        questions.append(item)
    
    return questions


def process_json_chapter(db: sqlite3.Connection, chapter_key: str, chapter_id: int, chapter_data: dict) -> Dict[str, int]:
    """
    处理 JSON 中的一个章节
    返回统计信息：{'matched': 匹配数量, 'updated': 更新数量, 'total': 总题目数}
    """
    questions = extract_questions_from_json_chapter(chapter_data)
    total = len(questions)
    matched = 0
    updated = 0
    
    print(f"\n📚 处理章节 {chapter_id}: {chapter_key}")
    print(f"   JSON 中的题目数: {total}")
    
    for idx, question_item in enumerate(questions, 1):
        question_text = question_item.get('q', '')
        if not question_text:
            continue
        
        # 在数据库中查找匹配的题目
        question_id = find_question_by_content(db, question_text, lang='it')
        
        if question_id:
            matched += 1
            # 更新章节编号
            if update_question_chapter(db, question_id, chapter_id):
                updated += 1
                if idx % 50 == 0:  # 每 50 题打印一次进度
                    print(f"   进度: {idx}/{total} (已匹配: {matched}, 已更新: {updated})")
        else:
            if idx <= 5:  # 只打印前 5 个未匹配的题目
                print(f"   ⚠️ 未匹配题目 {idx}: {question_text[:50]}...")
    
    print(f"   ✅ 匹配: {matched}/{total}, 更新: {updated}")
    
    return {'matched': matched, 'updated': updated, 'total': total}


def verify_assignment(db: sqlite3.Connection) -> Dict[int, int]:
    """验证章节分配结果"""
    cursor = db.cursor()
    
    # 统计每个章节的题目数量
    cursor.execute('''
        SELECT chapter, COUNT(*) as count
        FROM questions
        WHERE chapter IS NOT NULL
        GROUP BY chapter
        ORDER BY chapter
    ''')
    
    chapter_counts = {}
    for chapter_id, count in cursor.fetchall():
        chapter_counts[chapter_id] = count
    
    return chapter_counts


def main():
    """主函数"""
    print("=" * 70)
    print("🔄 数据库章节重新分配脚本")
    print("=" * 70)
    
    # 1. 查找 JSON 文件
    json_path = find_json_file()
    if not json_path:
        print("❌ 未找到 JSON 文件！")
        print("请确认 JSON 文件路径是否正确")
        sys.exit(1)
    
    print(f"✅ 找到 JSON 文件: {json_path}")
    
    # 2. 读取 JSON 文件
    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            json_data = json.load(f)
        print(f"✅ JSON 文件读取成功，包含 {len(json_data)} 个顶级键")
    except Exception as e:
        print(f"❌ 读取 JSON 文件失败: {e}")
        sys.exit(1)
    
    # 3. 构建章节映射表
    print("\n📋 构建章节映射表...")
    chapter_mapping = build_chapter_mapping(json_path)
    if not chapter_mapping:
        print("❌ 无法构建章节映射表！")
        sys.exit(1)
    
    print(f"✅ 章节映射表构建完成，共 {len(chapter_mapping)} 个章节")
    print("\n章节映射关系:")
    for key, chapter_id in sorted(chapter_mapping.items(), key=lambda x: x[1]):
        print(f"  {chapter_id:2d}. {key}")
    
    # 4. 连接数据库
    if not os.path.exists(DB_PATH):
        print(f"❌ 数据库文件不存在: {DB_PATH}")
        sys.exit(1)
    
    print(f"\n🔌 连接数据库: {DB_PATH}")
    try:
        db = sqlite3.connect(DB_PATH)
        print("✅ 数据库连接成功")
    except Exception as e:
        print(f"❌ 数据库连接失败: {e}")
        sys.exit(1)
    
    # 5. 检查 chapter 字段是否存在
    cursor = db.cursor()
    cursor.execute("PRAGMA table_info(questions)")
    columns = [col[1] for col in cursor.fetchall()]
    
    if 'chapter' not in columns:
        print("\n📝 添加 chapter 字段...")
        try:
            cursor.execute("ALTER TABLE questions ADD COLUMN chapter INTEGER")
            db.commit()
            print("✅ chapter 字段添加成功")
        except Exception as e:
            print(f"❌ 添加 chapter 字段失败: {e}")
            db.close()
            sys.exit(1)
    else:
        print("✅ chapter 字段已存在")
    
    # 6. 处理每个章节
    print("\n" + "=" * 70)
    print("🔄 开始处理章节...")
    print("=" * 70)
    
    total_stats = {'matched': 0, 'updated': 0, 'total': 0}
    
    for chapter_key, chapter_id in sorted(chapter_mapping.items(), key=lambda x: x[1]):
        if chapter_key in json_data:
            chapter_data = json_data[chapter_key]
            stats = process_json_chapter(db, chapter_key, chapter_id, chapter_data)
            total_stats['matched'] += stats['matched']
            total_stats['updated'] += stats['updated']
            total_stats['total'] += stats['total']
    
    print("\n" + "=" * 70)
    print("📊 处理统计")
    print("=" * 70)
    print(f"总题目数（JSON）: {total_stats['total']}")
    print(f"匹配成功: {total_stats['matched']}")
    print(f"更新成功: {total_stats['updated']}")
    print(f"匹配率: {total_stats['matched']/total_stats['total']*100:.1f}%" if total_stats['total'] > 0 else "N/A")
    
    # 7. 验证分配结果
    print("\n" + "=" * 70)
    print("✅ 验证章节分配结果")
    print("=" * 70)
    
    chapter_counts = verify_assignment(db)
    
    print("\n各章节题目数量:")
    for chapter_id in sorted(chapter_counts.keys()):
        count = chapter_counts[chapter_id]
        status = "✅" if count > 0 else "❌"
        print(f"  {status} 章节 {chapter_id:2d}: {count:4d} 题")
    
    # 检查未分配的题目
    cursor.execute("SELECT COUNT(*) FROM questions WHERE chapter IS NULL")
    unassigned_count = cursor.fetchone()[0]
    
    print(f"\n未分配的题目数: {unassigned_count}")
    if unassigned_count > 0:
        print("⚠️ 注意：仍有部分题目未分配章节")
    
    # 关闭数据库连接
    db.close()
    
    print("\n" + "=" * 70)
    print("🎉 章节分配完成！")
    print("=" * 70)


if __name__ == '__main__':
    main()

