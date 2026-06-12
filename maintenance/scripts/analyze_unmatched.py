#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
分析未匹配的题目，找出匹配失败的原因
并提供改进的匹配策略
"""

import json
import sqlite3
import os
from collections import defaultdict

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_JSON_PATH = os.path.abspath(
    os.path.join(PROJECT_ROOT, "..", "patente", "quizPatenteB2023.json")
)

# JSON分类到章节的映射（与improved_chapter_mapping.py中的一致）
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

def normalize_string(s):
    """标准化字符串"""
    if not s:
        return ""
    return s.lower().strip()

def analyze_matching_failures(json_path, db_path):
    """分析匹配失败的原因"""
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

    # 创建数据库题目的索引
    db_by_img = defaultdict(list)  # {img: [(id, answer, question), ...]}
    db_by_id = {}  # {id: (img, answer, question)}

    for row in cursor.fetchall():
        db_id, img, answer, question = row
        db_by_img[img].append((db_id, answer, question or ''))
        db_by_id[db_id] = (img, answer, question or '')

    # 分析JSON题目
    matched = set()
    unmatched_by_reason = {
        'no_img_match': [],
        'no_answer_match': [],
        'no_db_img': [],
        'multiple_matches': [],
        'json_only': []
    }

    json_questions_by_category = defaultdict(list)

    for category_key, category_data in json_data.items():
        chapter_id = JSON_TO_CHAPTER_MAPPING.get(category_key)
        if not chapter_id:
            # 这个分类没有映射，跳过
            continue

        if isinstance(category_data, dict):
            for sub_key, questions in category_data.items():
                if isinstance(questions, list):
                    for q in questions:
                        json_img = q.get('img', '')
                        json_question = q.get('q', '')
                        json_answer = q.get('a', False)

                        json_questions_by_category[category_key].append({
                            'img': json_img,
                            'question': json_question,
                            'answer': json_answer,
                            'chapter_id': chapter_id
                        })

                        # 尝试匹配
                        if json_img in db_by_img:
                            candidates = db_by_img[json_img]

                            # 通过答案和题目内容匹配
                            matched_id = None
                            for db_id, db_answer, db_question in candidates:
                                db_answer_bool = db_answer == 1
                                if db_answer_bool == json_answer:
                                    # 答案匹配，尝试内容匹配
                                    json_q_norm = normalize_string(json_question[:100])
                                    db_q_norm = normalize_string(db_question[:100])

                                    if json_q_norm == db_q_norm or json_q_norm in db_q_norm or db_q_norm in json_q_norm:
                                        matched_id = db_id
                                        matched.add(db_id)
                                        break

                            if not matched_id:
                                if len(candidates) > 1:
                                    unmatched_by_reason['multiple_matches'].append({
                                        'json': (json_img, json_question[:50], json_answer),
                                        'candidates': len(candidates)
                                    })
                                else:
                                    unmatched_by_reason['no_answer_match'].append({
                                        'json': (json_img, json_question[:50], json_answer),
                                        'db': candidates[0]
                                    })
                        else:
                            # JSON中的图片路径在数据库中不存在
                            unmatched_by_reason['no_db_img'].append({
                                'json': (json_img, json_question[:50], json_answer),
                                'category': category_key
                            })

    conn.close()

    return matched, unmatched_by_reason, json_questions_by_category

def generate_improved_matching_strategy(unmatched_by_reason, output_path):
    """生成改进的匹配策略说明"""
    lines = [
        "=" * 70,
        "未匹配题目分析报告",
        "=" * 70,
        "",
        f"未匹配原因统计:",
        "",
    ]

    total_unmatched = 0
    for reason, items in unmatched_by_reason.items():
        count = len(items)
        total_unmatched += count
        lines.append(f"  {reason}: {count} 道题目")

    lines.extend([
        "",
        f"总未匹配题目数: {total_unmatched}",
        "",
        "=" * 70,
        "改进匹配策略建议:",
        "=" * 70,
        "",
        "1. 图片路径不匹配 (no_db_img):",
        "   - 检查JSON和数据库中的图片路径格式是否一致",
        "   - 可能需要路径标准化（去除前导/，或添加前缀）",
        "",
        "2. 答案不匹配 (no_answer_match):",
        "   - 检查数据库中的answer字段格式（0/1 vs True/False）",
        "   - 可能需要通过题目内容进一步匹配",
        "",
        "3. 多个候选题目 (multiple_matches):",
        "   - 同一张图片对应多道题目（相同图片，不同问题）",
        "   - 需要通过题目内容精确匹配",
        "",
        "4. 无映射分类:",
        "   - 检查JSON中是否有分类没有在映射表中",
        "   - 添加缺失的映射关系",
        "",
    ])

    # 添加示例未匹配题目
    lines.extend([
        "",
        "=" * 70,
        "未匹配题目示例（前10个）:",
        "=" * 70,
        "",
    ])

    for reason, items in unmatched_by_reason.items():
        if items:
            lines.append(f"\n【{reason}】示例:")
            for i, item in enumerate(items[:5], 1):
                lines.append(f"  {i}. {item}")
            if len(items) > 5:
                lines.append(f"  ... 还有 {len(items) - 5} 个")

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

if __name__ == '__main__':
    json_path = os.environ.get("PATENTE_JSON_PATH", DEFAULT_JSON_PATH)
    db_path = os.path.join(PROJECT_ROOT, "assets", "italy_quiz.db")
    output_path = os.path.join(SCRIPT_DIR, 'unmatched_analysis.txt')

    print("=" * 70)
    print("📊 分析未匹配题目")
    print("=" * 70)

    print("\n1. 分析匹配失败原因...")
    matched, unmatched_by_reason, json_by_category = analyze_matching_failures(json_path, db_path)

    print(f"\n✅ 匹配成功的题目: {len(matched)}")
    print(f"\n未匹配题目统计:")
    total_unmatched = 0
    for reason, items in unmatched_by_reason.items():
        count = len(items)
        total_unmatched += count
        print(f"  {reason}: {count}")

    print(f"\n总未匹配: {total_unmatched}")

    print("\n2. 生成分析报告...")
    generate_improved_matching_strategy(unmatched_by_reason, output_path)
    print(f"✅ 报告已保存: {output_path}")

    print("\n3. JSON分类统计:")
    for category, questions in sorted(json_by_category.items(), key=lambda x: len(x[1]), reverse=True)[:10]:
        print(f"  {category}: {len(questions)} 道题目")

    print("\n" + "=" * 70)
