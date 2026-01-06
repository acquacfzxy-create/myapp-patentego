#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
详细分析未匹配题目的原因
"""

import json
import sqlite3
import re
from collections import defaultdict
from difflib import SequenceMatcher

def normalize_string(s):
    """标准化字符串"""
    if not s:
        return ""
    s = s.lower().strip()
    s = re.sub(r'[^\w\s]', '', s)
    s = re.sub(r'\s+', ' ', s)
    return s

def similarity(a, b):
    """计算相似度"""
    return SequenceMatcher(None, a, b).ratio()

# JSON分类到章节的映射
JSON_TO_CHAPTER_MAPPING = {
    "segnali-pericolo": 1, "segnali-divieto": 1, "segnali-obbligo": 1,
    "segnali-precedenza": 1, "segnali-indicazione": 1,
    "segnaletica-orizzontale-ostacoli": 1, "segnali-complementari-cantiere": 1,
    "pannelli-integrativi": 1, "precedenza-incroci": 2,
    "fermata-sosta-arresto": 3, "limiti-di-velocita": 4, "sorpasso": 5,
    "distanza-di-sicurezza": 6, "definizioni-generali-doveri-strada": 7,
    "norme-di-circolazione": 7, "elementi-veicolo-manutenzione-comportamenti": 9,
    "patente-punti-documenti": 10, "incidenti-stradali-comportamenti": 11,
    "alcool-droga-primo-soccorso": 12, "norme-varie-autostrade-pannelli": 13,
    "semafori-vigili": 14, "luci-dispositivi-acustici": 14,
    "cinture-casco-sicurezza": 15, "consumi-ambiente-inquinamento": 22,
    "responsabilita-civile-penale-e-assicurazione": 24,
}

def analyze_unmatched_detailed(json_path, db_path, sql_path):
    """详细分析未匹配的原因"""
    # 加载JSON
    with open(json_path, 'r', encoding='utf-8') as f:
        json_data = json.load(f)
    
    # 连接数据库
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT q.id, q.img, q.answer, t_q.content as question
        FROM questions q
        LEFT JOIN translations t_q ON q.id = t_q.question_id 
            AND t_q.lang = 'it' AND t_q.type = 'q'
    """)
    
    db_by_img = defaultdict(list)
    db_by_id = {}
    
    for row in cursor.fetchall():
        db_id, img, answer, question = row
        db_by_img[img or ''].append((db_id, answer, question or ''))
        db_by_id[db_id] = (img, answer, question or '')
    
    # 读取已匹配的题目ID
    matched_ids = set()
    if sql_path:
        try:
            with open(sql_path, 'r', encoding='utf-8') as f:
                sql_content = f.read()
            id_pattern = r"'(\d+[-]?\d*)'"
            matched_ids = set(re.findall(id_pattern, sql_content))
        except:
            pass
    
    # 分析未匹配
    unmatched_analysis = {
        'no_mapping': [],  # 没有章节映射
        'empty_img': [],   # 图片为空
        'img_not_found': [],  # 图片在数据库中不存在
        'low_similarity': [],  # 相似度太低（<0.8）
        'answer_mismatch': [],  # 答案不匹配
    }
    
    json_total = 0
    matched_count = 0
    
    for category_key, category_data in json_data.items():
        chapter_id = JSON_TO_CHAPTER_MAPPING.get(category_key)
        
        if isinstance(category_data, dict):
            for sub_key, questions in category_data.items():
                if isinstance(questions, list):
                    for q in questions:
                        json_total += 1
                        json_img = q.get('img', '')
                        json_question = q.get('q', '')
                        json_answer = q.get('a', False)
                        
                        # 检查是否有章节映射
                        if not chapter_id:
                            unmatched_analysis['no_mapping'].append({
                                'category': category_key,
                                'question': json_question[:80]
                            })
                            continue
                        
                        # 检查图片路径
                        if not json_img or json_img.strip() == '':
                            unmatched_analysis['empty_img'].append({
                                'category': category_key,
                                'chapter_id': chapter_id,
                                'question': json_question[:80]
                            })
                            continue
                        
                        # 查找数据库中的候选题目
                        candidates = db_by_img.get(json_img, [])
                        
                        if not candidates:
                            unmatched_analysis['img_not_found'].append({
                                'category': category_key,
                                'chapter_id': chapter_id,
                                'img': json_img,
                                'question': json_question[:80]
                            })
                            continue
                        
                        # 尝试匹配
                        json_q_norm = normalize_string(json_question[:200])
                        best_match = None
                        best_sim = 0
                        
                        for db_id, db_answer, db_question in candidates:
                            db_answer_bool = db_answer == 1
                            
                            # 检查答案是否匹配
                            if db_answer_bool == json_answer:
                                if db_question:
                                    db_q_norm = normalize_string(db_question[:200])
                                    sim = similarity(json_q_norm, db_q_norm)
                                    if sim > best_sim:
                                        best_sim = sim
                                        best_match = db_id
                                elif len(candidates) == 1:
                                    best_match = db_id
                                    best_sim = 1.0
                        
                        # 判断匹配结果
                        if best_match:
                            if best_match in matched_ids:
                                matched_count += 1
                            elif best_sim < 0.8:
                                unmatched_analysis['low_similarity'].append({
                                    'category': category_key,
                                    'chapter_id': chapter_id,
                                    'img': json_img,
                                    'similarity': best_sim,
                                    'json_question': json_question[:80],
                                    'db_question': db_by_id[best_match][2][:80] if best_match in db_by_id else ''
                                })
                        else:
                            # 答案不匹配
                            unmatched_analysis['answer_mismatch'].append({
                                'category': category_key,
                                'chapter_id': chapter_id,
                                'img': json_img,
                                'candidates_count': len(candidates),
                                'question': json_question[:80]
                            })
    
    conn.close()
    return unmatched_analysis, json_total, matched_count

if __name__ == '__main__':
    json_path = '/Users/fabio/Desktop/patente/quizPatenteB2023.json'
    db_path = '/Users/fabio/Desktop/assets/assets/italy_quiz.db'
    sql_path = '/Users/fabio/Desktop/assets/scripts/assign_chapters_v2.sql'
    
    print("=" * 70)
    print("📊 详细未匹配原因分析")
    print("=" * 70)
    
    analysis, json_total, matched_count = analyze_unmatched_detailed(json_path, db_path, sql_path)
    
    print(f"\nJSON题目总数: {json_total}")
    print(f"已匹配: {matched_count} 道题目")
    print(f"未匹配: {json_total - matched_count} 道题目")
    
    print(f"\n【未匹配原因详细统计】")
    total_unmatched = 0
    for reason, items in analysis.items():
        count = len(items)
        total_unmatched += count
        if count > 0:
            print(f"\n{reason}: {count} 道题目")
            
            # 显示示例
            if items:
                print("  示例（前3个）:")
                for i, item in enumerate(items[:3], 1):
                    print(f"    {i}. ", end='')
                    if 'question' in item:
                        print(f"题目: {item['question']}...")
                    if 'img' in item:
                        print(f"      图片: {item['img']}")
                    if 'similarity' in item:
                        print(f"      相似度: {item['similarity']:.2f}")
                    if 'candidates_count' in item:
                        print(f"      候选题目数: {item['candidates_count']}")
                    if 'category' in item:
                        print(f"      分类: {item['category']}")
    
    print(f"\n总未匹配: {total_unmatched} 道题目")
    
    # 按分类统计
    print(f"\n【未匹配题目按分类统计】")
    categories_count = defaultdict(int)
    for reason, items in analysis.items():
        for item in items:
            if 'category' in item:
                categories_count[item['category']] += 1
    
    for cat, count in sorted(categories_count.items(), key=lambda x: x[1], reverse=True)[:10]:
        print(f"  {cat}: {count} 道题目")
    
    print("\n" + "=" * 70)

