#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
创建JSON分类到章节的映射关系
并生成章节分配脚本
"""

import json
import sys
import os
import sqlite3

# JSON分类到章节ID的映射（基于名称匹配）
# 这个映射是基于分类名称的相似性，可能需要手动调整
JSON_TO_CHAPTER_MAPPING = {
    # 重点章节 (1-15)
    "segnali-pericolo": 1,  # Segnaletica stradale (交通标志)
    "segnali-divieto": 1,
    "segnali-obbligo": 1,
    "segnali-precedenza": 1,
    "segnali-indicazione": 1,
    "segnaletica-orizzontale-ostacoli": 1,
    "semafori-vigili": 1,
    "segnali-complementari-cantiere": 1,
    "pannelli-integrativi": 1,
    
    "precedenza-incroci": 2,  # Precedenza (优先权)
    
    "fermata-sosta-arresto": 3,  # Sosta e fermata (停车与停止)
    
    "limiti-di-velocita": 4,  # Velocità (速度)
    
    "sorpasso": 5,  # Sorpasso (超车)
    
    "distanza-di-sicurezza": 6,  # Distanza di sicurezza (安全距离)
    
    "definizioni-generali-doveri-strada": 7,  # Incroci (交叉路口) - 可能需要调整
    "norme-di-circolazione": 7,
    
    "norme-varie-autostrade-pannelli": 8,  # Curve e cambiamenti di carreggiata (弯道与变道) - 可能需要调整
    
    "luci-dispositivi-acustici": 9,  # Veicoli e loro caratteristiche (车辆及其特征) - 可能需要调整
    
    "cinture-casco-sicurezza": 10,  # Norme di comportamento (行为规范) - 可能需要调整
    
    "patente-punti-documenti": 11,  # Documenti (文件) - 可能需要调整
    
    "incidenti-stradali-comportamenti": 12,  # Incidenti (事故) - 可能需要调整
    
    "alcool-droga-primo-soccorso": 13,  # Guida ecologica (生态驾驶) - 可能需要调整
    
    "responsabilita-civile-penale-e-assicurazione": 14,  # Responsabilità civile e penale (民事责任和刑事责任)
    
    "consumi-ambiente-inquinamento": 15,  # Inquinamento (污染)
    
    # 次要章节 (16-25) - 需要根据实际章节配置调整
    "elementi-veicolo-manutenzione-comportamenti": 16,  # Elementi costitutivi del veicolo (车辆构成要素)
    
    # 注意：上面的映射是初步估计，需要根据实际的 chapter_config.dart 中的章节定义来调整
}

def load_json_data(json_path):
    """加载JSON数据"""
    with open(json_path, 'r', encoding='utf-8') as f:
        return json.load(f)

def extract_questions_by_category(json_data):
    """按分类提取所有题目"""
    questions_by_category = {}
    
    for category_key, category_data in json_data.items():
        if isinstance(category_data, dict):
            questions_by_category[category_key] = []
            for sub_key, questions in category_data.items():
                if isinstance(questions, list):
                    for question in questions:
                        questions_by_category[category_key].append({
                            'img': question.get('img', ''),
                            'q': question.get('q', ''),
                            'a': question.get('a', False),
                            'category': category_key,
                            'sub_category': sub_key
                        })
    
    return questions_by_category

def match_questions_to_database(json_questions, db_path):
    """将JSON题目匹配到数据库题目"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # 获取数据库中所有题目
    cursor.execute("SELECT id, img, answer FROM questions")
    db_questions = cursor.fetchall()
    
    # 创建匹配映射：{json_question_key: db_question_id}
    matches = {}
    
    # 按图片路径匹配（最可靠的方式）
    img_to_db_ids = {}
    for db_id, db_img, db_answer in db_questions:
        if db_img:
            if db_img not in img_to_db_ids:
                img_to_db_ids[db_img] = []
            img_to_db_ids[db_img].append((db_id, db_answer))
    
    # 匹配JSON题目到数据库题目
    matched_count = 0
    for category_key, questions in json_questions.items():
        for q in questions:
            json_img = q['img']
            json_answer = q['a']
            
            # 通过图片路径匹配
            if json_img in img_to_db_ids:
                # 如果有多个题目使用同一张图片，还需要通过答案来进一步匹配
                candidates = img_to_db_ids[json_img]
                if len(candidates) == 1:
                    # 只有一个候选，直接匹配
                    db_id, _ = candidates[0]
                    matches[(category_key, json_img, json_answer)] = db_id
                    matched_count += 1
                else:
                    # 多个候选，通过答案匹配
                    for db_id, db_answer in candidates:
                        if (db_answer == 1 and json_answer) or (db_answer == 0 and not json_answer):
                            matches[(category_key, json_img, json_answer)] = db_id
                            matched_count += 1
                            break
    
    conn.close()
    return matches, matched_count

def generate_sql_script(matches, mapping, output_path):
    """生成SQL分配脚本"""
    # 按章节分组
    chapter_to_question_ids = {}
    
    for (category_key, _, _), db_id in matches.items():
        chapter_id = mapping.get(category_key)
        if chapter_id:
            if chapter_id not in chapter_to_question_ids:
                chapter_to_question_ids[chapter_id] = []
            chapter_to_question_ids[chapter_id].append(db_id)
    
    # 生成SQL
    sql_lines = [
        "-- 自动生成的章节分配SQL脚本",
        "-- 基于JSON文件的分类结构",
        "",
        "BEGIN TRANSACTION;",
        ""
    ]
    
    for chapter_id in sorted(chapter_to_question_ids.keys()):
        question_ids = chapter_to_question_ids[chapter_id]
        if question_ids:
            # 分批更新（SQLite的IN子句有参数限制）
            batch_size = 500
            for i in range(0, len(question_ids), batch_size):
                batch = question_ids[i:i+batch_size]
                placeholders = ','.join(['?' for _ in batch])
                sql_lines.append(f"UPDATE questions SET chapter_id = {chapter_id} WHERE id IN ({placeholders});")
                sql_lines.append(f"-- 章节 {chapter_id}: {len(batch)} 道题目")
            
            sql_lines.append(f"-- 章节 {chapter_id} 总共分配 {len(question_ids)} 道题目")
            sql_lines.append("")
    
    sql_lines.extend([
        "COMMIT;",
        "",
        "-- 验证分配结果",
        "SELECT chapter_id, COUNT(*) as count FROM questions WHERE chapter_id IS NOT NULL GROUP BY chapter_id ORDER BY chapter_id;"
    ])
    
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sql_lines))
    
    return chapter_to_question_ids

if __name__ == '__main__':
    json_path = '/Users/fabio/Desktop/patente/quizPatenteB2023.json'
    db_path = '/Users/fabio/Desktop/assets/assets/italy_quiz.db'
    output_path = os.path.join(os.path.dirname(__file__), 'assign_chapters_from_json.sql')
    
    print("=" * 70)
    print("📋 生成章节分配脚本")
    print("=" * 70)
    
    # 加载JSON数据
    print("\n1. 加载JSON数据...")
    json_data = load_json_data(json_path)
    
    # 提取题目
    print("2. 提取题目...")
    json_questions = extract_questions_by_category(json_data)
    total_json_questions = sum(len(qs) for qs in json_questions.values())
    print(f"   从JSON中提取 {total_json_questions} 道题目")
    
    # 匹配到数据库
    print("3. 匹配题目到数据库...")
    matches, matched_count = match_questions_to_database(json_questions, db_path)
    print(f"   成功匹配 {matched_count} 道题目")
    
    # 生成SQL脚本
    print("4. 生成SQL脚本...")
    chapter_to_ids = generate_sql_script(matches, JSON_TO_CHAPTER_MAPPING, output_path)
    
    print(f"\n✅ SQL脚本已生成: {output_path}")
    print("\n章节分配统计:")
    for chapter_id in sorted(chapter_to_ids.keys()):
        print(f"  章节 {chapter_id}: {len(chapter_to_ids[chapter_id])} 道题目")
    
    print("\n⚠️  注意：映射关系需要根据实际的章节配置手动调整！")
    print("=" * 70)

