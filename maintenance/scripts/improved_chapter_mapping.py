#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
改进的章节映射和题目匹配脚本
通过题目内容和图片路径匹配JSON题目到数据库题目
"""

import json
import sqlite3
import os
import hashlib

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_JSON_PATH = os.path.abspath(
    os.path.join(PROJECT_ROOT, "..", "patente", "quizPatenteB2023.json")
)

# 改进的映射关系（基于关键词匹配）
JSON_TO_CHAPTER_MAPPING = {
    # 章节 1: Segnaletica stradale (交通标志)
    "segnali-pericolo": 1,
    "segnali-divieto": 1,
    "segnali-obbligo": 1,
    "segnali-precedenza": 1,
    "segnali-indicazione": 1,
    "segnaletica-orizzontale-ostacoli": 1,
    "segnali-complementari-cantiere": 1,
    "pannelli-integrativi": 1,

    # 章节 2: Precedenza (优先权)
    "precedenza-incroci": 2,

    # 章节 3: Sosta e fermata (停车与停止)
    "fermata-sosta-arresto": 3,

    # 章节 4: Velocità (速度)
    "limiti-di-velocita": 4,

    # 章节 5: Sorpasso (超车)
    "sorpasso": 5,

    # 章节 6: Distanza di sicurezza (安全距离)
    "distanza-di-sicurezza": 6,

    # 章节 7: Incroci (交叉路口)
    "definizioni-generali-doveri-strada": 7,
    "norme-di-circolazione": 7,

    # 章节 8: Curve e cambiamenti di carreggiata (弯道与变道)
    # (norme-di-circolazione 的一部分可能属于这里，但先用7)

    # 章节 9: Veicoli e loro caratteristiche (车辆及其特征)
    "elementi-veicolo-manutenzione-comportamenti": 9,

    # 章节 10: Documenti di circolazione (行驶证件)
    "patente-punti-documenti": 10,

    # 章节 11: Guida in condizioni difficili (困难条件下的驾驶)
    "incidenti-stradali-comportamenti": 11,

    # 章节 12: Comportamento in caso di incidente (事故处理)
    "alcool-droga-primo-soccorso": 12,

    # 章节 13: Limiti e divieti (限制与禁止)
    "norme-varie-autostrade-pannelli": 13,

    # 章节 14: Segnali luminosi (交通信号灯)
    "semafori-vigili": 14,
    "luci-dispositivi-acustici": 14,

    # 章节 15: Regole generali di comportamento (一般行为规则)
    "cinture-casco-sicurezza": 15,

    # 章节 22: Guida ecologica (环保驾驶)
    "consumi-ambiente-inquinamento": 22,

    # 章节 24: Norme per la circolazione dei veicoli pubblici (公共车辆通行规则)
    "responsabilita-civile-penale-e-assicurazione": 24,
}

def normalize_string(s):
    """标准化字符串（用于匹配）"""
    if not s:
        return ""
    # 转换为小写，移除标点符号
    s = s.lower().strip()
    # 移除常见的标点符号
    for char in ".,;:!?'\"()[]{}":
        s = s.replace(char, "")
    return s

def match_questions_improved(json_path, db_path):
    """改进的题目匹配方法"""
    # 加载JSON
    with open(json_path, 'r', encoding='utf-8') as f:
        json_data = json.load(f)

    # 连接数据库
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 获取数据库中所有题目的意大利语内容
    cursor.execute("""
        SELECT q.id, q.img, q.answer, t_q.content as question
        FROM questions q
        LEFT JOIN translations t_q ON q.id = t_q.question_id
            AND t_q.lang = 'it' AND t_q.type = 'q'
    """)
    db_questions = {row[0]: {
        'img': row[1],
        'answer': row[2],
        'question': row[3] or ''
    } for row in cursor.fetchall()}

    # 创建匹配映射
    matches = {}  # {(category, img, question_hash): db_id}
    unmatched_json = []

    question_counter = 0

    # 遍历JSON中的所有题目
    for category_key, category_data in json_data.items():
        chapter_id = JSON_TO_CHAPTER_MAPPING.get(category_key)
        if not chapter_id:
            continue

        if isinstance(category_data, dict):
            for sub_key, questions in category_data.items():
                if isinstance(questions, list):
                    for q in questions:
                        question_counter += 1
                        json_img = q.get('img', '')
                        json_question = q.get('q', '')
                        json_answer = q.get('a', False)

                        # 方法1: 通过图片路径匹配
                        matched_db_ids = []
                        for db_id, db_q in db_questions.items():
                            if db_q['img'] == json_img:
                                # 如果图片匹配，进一步通过答案匹配
                                db_answer_bool = db_q['answer'] == 1
                                if db_answer_bool == json_answer:
                                    # 如果可能，也通过题目内容匹配（前50个字符）
                                    if db_q['question']:
                                        json_q_normalized = normalize_string(json_question[:100])
                                        db_q_normalized = normalize_string(db_q['question'][:100])
                                        if json_q_normalized == db_q_normalized or json_q_normalized in db_q_normalized or db_q_normalized in json_q_normalized:
                                            matched_db_ids.append(db_id)
                                            break
                                        elif len(matched_db_ids) == 0:  # 如果内容不完全匹配但图片和答案匹配
                                            matched_db_ids.append(db_id)
                                    else:
                                        matched_db_ids.append(db_id)
                                        break

                        if matched_db_ids:
                            matches[(category_key, json_img, json_question[:50])] = (matched_db_ids[0], chapter_id)
                        else:
                            unmatched_json.append((category_key, json_img, json_question[:50]))

    conn.close()
    return matches, unmatched_json, question_counter

def generate_sql_from_matches(matches, output_path):
    """从匹配结果生成SQL脚本"""
    # 按章节分组
    chapter_to_ids = {}

    for (category, img, q_preview), (db_id, chapter_id) in matches.items():
        if chapter_id not in chapter_to_ids:
            chapter_to_ids[chapter_id] = []
        chapter_to_ids[chapter_id].append(db_id)

    # 生成SQL（使用实际的ID值，而不是占位符）
    sql_lines = [
        "-- 自动生成的章节分配SQL脚本",
        "-- 基于JSON文件的分类结构和题目匹配",
        "",
        "BEGIN TRANSACTION;",
        ""
    ]

    total_assigned = 0
    for chapter_id in sorted(chapter_to_ids.keys()):
        question_ids = list(set(chapter_to_ids[chapter_id]))  # 去重
        if question_ids:
            # 将ID转换为字符串并用单引号包围
            id_strings = [f"'{id_val}'" for id_val in question_ids]

            # 分批更新（SQLite的IN子句可以处理大量值，但为了可读性，我们分批处理）
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
    output_path = os.path.join(SCRIPT_DIR, 'assign_chapters_improved.sql')

    print("=" * 70)
    print("📋 改进的章节分配脚本生成")
    print("=" * 70)

    print("\n1. 匹配题目...")
    matches, unmatched, total_json = match_questions_improved(json_path, db_path)

    print(f"   JSON题目总数: {total_json}")
    print(f"   成功匹配: {len(matches)}")
    print(f"   未匹配: {len(unmatched)}")
    print(f"   匹配率: {len(matches)/total_json*100:.1f}%")

    print("\n2. 生成SQL脚本...")
    chapter_to_ids, total_assigned = generate_sql_from_matches(matches, output_path)

    print(f"\n✅ SQL脚本已生成: {output_path}")
    print(f"\n章节分配统计 (去重后):")
    for chapter_id in sorted(chapter_to_ids.keys()):
        unique_ids = len(set(chapter_to_ids[chapter_id]))
        print(f"  章节 {chapter_id:2d}: {unique_ids} 道题目")

    print(f"\n总共将分配 {total_assigned} 道题目")
    print("\n" + "=" * 70)
