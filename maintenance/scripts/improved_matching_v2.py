#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
改进的题目匹配脚本 V2
使用多种策略匹配题目：
1. 图片路径匹配（标准化路径）
2. 题目内容模糊匹配
3. 答案匹配
"""

import json
import sqlite3
import os
import re
from collections import defaultdict
from difflib import SequenceMatcher

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_JSON_PATH = os.path.abspath(
    os.path.join(PROJECT_ROOT, "..", "patente", "quizPatenteB2023.json")
)

# JSON分类到章节的映射
JSON_TO_CHAPTER_MAPPING = {
    "segnali-pericolo": 1,
    "segnali-divieto": 1,
    "segnali-obbligo": 1,
    "segnali-precedenza": 1,
    "segnali-indicazione": 1,
    "segnaletica-orizzontale-ostacoli": 1,
    "segnali-complementari-cantiere": 1,
    "pannelli-integrativi": 1,
    "precedenza-incroci": 2,
    "fermata-sosta-arresto": 3,
    "limiti-di-velocita": 4,
    "sorpasso": 5,
    "distanza-di-sicurezza": 6,
    "definizioni-generali-doveri-strada": 7,
    "norme-di-circolazione": 7,
    "elementi-veicolo-manutenzione-comportamenti": 9,
    "patente-punti-documenti": 10,
    "incidenti-stradali-comportamenti": 11,
    "alcool-droga-primo-soccorso": 12,
    "norme-varie-autostrade-pannelli": 13,
    "semafori-vigili": 14,
    "luci-dispositivi-acustici": 14,
    "cinture-casco-sicurezza": 15,
    "consumi-ambiente-inquinamento": 22,
    "responsabilita-civile-penale-e-assicurazione": 24,
}

def normalize_img_path(img_path):
    """标准化图片路径"""
    if not img_path:
        return ""
    # 移除前导斜杠，统一格式
    img_path = img_path.strip()
    if img_path.startswith('/'):
        img_path = img_path[1:]
    # 统一使用正斜杠
    img_path = img_path.replace('\\', '/')
    return img_path.lower()

def normalize_string(s):
    """标准化字符串（用于匹配）"""
    if not s:
        return ""
    s = s.lower().strip()
    # 移除标点符号
    s = re.sub(r'[^\w\s]', '', s)
    # 移除多余空格
    s = re.sub(r'\s+', ' ', s)
    return s

def similarity(a, b):
    """计算两个字符串的相似度"""
    return SequenceMatcher(None, a, b).ratio()

def match_questions_v2(json_path, db_path, similarity_threshold=0.8):
    """改进的匹配方法"""
    # 加载JSON
    with open(json_path, 'r', encoding='utf-8') as f:
        json_data = json.load(f)

    # 连接数据库
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 获取数据库中所有题目
    cursor.execute("""
        SELECT q.id, q.img, q.answer, t_q.content as question
        FROM questions q
        LEFT JOIN translations t_q ON q.id = t_q.question_id
            AND t_q.lang = 'it' AND t_q.type = 'q'
    """)

    # 创建多个索引以提高匹配效率
    db_by_img_normalized = defaultdict(list)  # 标准化图片路径索引
    db_by_img_original = defaultdict(list)    # 原始图片路径索引
    db_by_id = {}  # ID索引

    for row in cursor.fetchall():
        db_id, img, answer, question = row
        img_normalized = normalize_img_path(img or '')
        img_original = (img or '').strip()

        db_by_img_normalized[img_normalized].append((db_id, answer, question or ''))
        if img_original:
            db_by_img_original[img_original].append((db_id, answer, question or ''))

        db_by_id[db_id] = (img, answer, question or '')

    # 匹配结果
    matches = {}  # {(category, img, question_preview): (db_id, chapter_id)}
    unmatched = []
    match_stats = {
        'by_img_exact': 0,
        'by_img_normalized': 0,
        'by_content': 0,
        'by_content_fuzzy': 0,
        'failed': 0
    }

    json_question_count = 0

    # 遍历JSON中的所有题目
    for category_key, category_data in json_data.items():
        chapter_id = JSON_TO_CHAPTER_MAPPING.get(category_key)
        if not chapter_id:
            continue

        if isinstance(category_data, dict):
            for sub_key, questions in category_data.items():
                if isinstance(questions, list):
                    for q in questions:
                        json_question_count += 1
                        json_img = q.get('img', '')
                        json_question = q.get('q', '')
                        json_answer = q.get('a', False)

                        matched_db_id = None
                        match_method = None

                        # 策略1: 通过标准化图片路径匹配
                        json_img_normalized = normalize_img_path(json_img)
                        candidates = db_by_img_normalized.get(json_img_normalized, [])

                        # 策略2: 如果没有找到，尝试原始路径
                        if not candidates:
                            candidates = db_by_img_original.get(json_img.strip(), [])

                        if candidates:
                            # 在候选题目中通过答案和内容匹配
                            json_q_normalized = normalize_string(json_question)

                            best_match = None
                            best_similarity = 0

                            for db_id, db_answer, db_question in candidates:
                                db_answer_bool = db_answer == 1

                                # 首先检查答案是否匹配
                                if db_answer_bool == json_answer:
                                    # 答案匹配，检查内容相似度
                                    if db_question:
                                        db_q_normalized = normalize_string(db_question)
                                        sim = similarity(json_q_normalized[:200], db_q_normalized[:200])

                                        # 如果相似度很高，直接匹配
                                        if sim >= similarity_threshold:
                                            matched_db_id = db_id
                                            match_method = 'by_content'
                                            break

                                        # 保存最佳匹配
                                        if sim > best_similarity:
                                            best_similarity = sim
                                            best_match = db_id
                                    else:
                                        # 数据库中没有题目内容，但有图片和答案匹配
                                        if len(candidates) == 1:
                                            matched_db_id = db_id
                                            match_method = 'by_img_exact'
                                            break

                            # 如果没有精确匹配，使用最佳匹配（如果相似度足够）
                            if not matched_db_id and best_match and best_similarity >= 0.6:
                                matched_db_id = best_match
                                match_method = 'by_content_fuzzy'

                            # 如果只有一个候选且答案匹配，直接使用
                            if not matched_db_id and len(candidates) == 1:
                                db_id, db_answer, _ = candidates[0]
                                if (db_answer == 1) == json_answer:
                                    matched_db_id = db_id
                                    match_method = 'by_img_normalized'

                        if matched_db_id:
                            matches[(category_key, json_img, json_question[:50])] = (matched_db_id, chapter_id)
                            match_stats[match_method if match_method else 'by_img_exact'] += 1
                        else:
                            unmatched.append({
                                'category': category_key,
                                'chapter_id': chapter_id,
                                'img': json_img,
                                'question': json_question[:100],
                                'answer': json_answer
                            })
                            match_stats['failed'] += 1

    conn.close()

    return matches, unmatched, match_stats, json_question_count

def generate_sql_from_matches_v2(matches, output_path):
    """生成SQL脚本"""
    # 按章节分组
    chapter_to_ids = defaultdict(set)

    for (category, img, q_preview), (db_id, chapter_id) in matches.items():
        chapter_to_ids[chapter_id].add(db_id)

    # 生成SQL
    sql_lines = [
        "-- 改进的章节分配SQL脚本 (V2)",
        "-- 使用多种匹配策略：图片路径标准化、内容相似度匹配",
        "",
        "BEGIN TRANSACTION;",
        ""
    ]

    total_assigned = 0
    for chapter_id in sorted(chapter_to_ids.keys()):
        question_ids = list(chapter_to_ids[chapter_id])
        if question_ids:
            # 将ID转换为字符串并用单引号包围
            id_strings = [f"'{id_val}'" for id_val in question_ids]

            # 分批更新
            batch_size = 500
            for i in range(0, len(id_strings), batch_size):
                batch = id_strings[i:i+batch_size]
                ids_str = ','.join(batch)
                sql_lines.append(f"UPDATE questions SET chapter_id = {chapter_id} WHERE id IN ({ids_str});")

            sql_lines.append(f"-- 章节 {chapter_id}: {len(question_ids)} 道题目")
            sql_lines.append("")
            total_assigned += len(question_ids)

    sql_lines.extend([
        "COMMIT;",
        "",
        f"-- 总共分配 {total_assigned} 道题目",
        "",
        "-- 验证分配结果",
        "SELECT chapter_id, COUNT(*) as count FROM questions WHERE chapter_id IS NOT NULL GROUP BY chapter_id ORDER BY chapter_id;",
        "",
        "-- 查看未分配的题目数量",
        "SELECT COUNT(*) as unassigned FROM questions WHERE chapter_id IS NULL;"
    ])

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sql_lines))

    return chapter_to_ids, total_assigned

if __name__ == '__main__':
    json_path = os.environ.get("PATENTE_JSON_PATH", DEFAULT_JSON_PATH)
    db_path = os.path.join(PROJECT_ROOT, "assets", "italy_quiz.db")
    output_path = os.path.join(SCRIPT_DIR, 'assign_chapters_v2.sql')
    unmatched_output = os.path.join(SCRIPT_DIR, 'unmatched_v2.json')

    print("=" * 70)
    print("📋 改进的章节分配脚本生成 (V2)")
    print("=" * 70)

    print("\n1. 使用改进的匹配策略...")
    matches, unmatched, stats, json_total = match_questions_v2(json_path, db_path)

    print(f"\n   JSON题目总数: {json_total}")
    print(f"   成功匹配: {len(matches)}")
    print(f"   未匹配: {len(unmatched)}")
    print(f"   匹配率: {len(matches)/json_total*100:.1f}%")

    print(f"\n   匹配方法统计:")
    for method, count in stats.items():
        print(f"     {method}: {count}")

    print("\n2. 生成SQL脚本...")
    chapter_to_ids, total_assigned = generate_sql_from_matches_v2(matches, output_path)

    print(f"\n✅ SQL脚本已生成: {output_path}")
    print(f"\n章节分配统计 (去重后):")
    for chapter_id in sorted(chapter_to_ids.keys()):
        unique_ids = len(chapter_to_ids[chapter_id])
        print(f"  章节 {chapter_id:2d}: {unique_ids} 道题目")

    print(f"\n总共将分配 {total_assigned} 道题目")

    # 保存未匹配的题目（用于进一步分析）
    import json as json_lib
    with open(unmatched_output, 'w', encoding='utf-8') as f:
        json_lib.dump(unmatched[:100], f, ensure_ascii=False, indent=2)
    print(f"\n✅ 未匹配题目示例已保存: {unmatched_output} (前100个)")

    print("\n" + "=" * 70)
