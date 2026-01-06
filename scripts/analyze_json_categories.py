#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
分析 JSON 文件中的分类结构
提取题目ID并生成章节分配脚本
"""

import json
import sys
import os

# 添加项目根目录到路径
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def analyze_json_structure(json_path):
    """分析JSON文件结构"""
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    print("=" * 70)
    print("📋 JSON 文件分类结构分析")
    print("=" * 70)
    
    # 顶层分类
    top_level_categories = list(data.keys())
    print(f"\n✅ 找到 {len(top_level_categories)} 个顶层分类:\n")
    
    category_stats = {}
    for cat_key in top_level_categories:
        category_data = data[cat_key]
        if isinstance(category_data, dict):
            sub_categories = list(category_data.keys())
            total_questions = 0
            for sub_key in sub_categories:
                questions = category_data[sub_key]
                if isinstance(questions, list):
                    total_questions += len(questions)
            
            category_stats[cat_key] = {
                'sub_categories': len(sub_categories),
                'total_questions': total_questions
            }
            
            print(f"  📁 {cat_key}")
            print(f"     └─ {len(sub_categories)} 个子分类, 共 {total_questions} 道题目")
            if len(sub_categories) > 0:
                # 显示前3个子分类作为示例
                for sub_key in sub_categories[:3]:
                    sub_questions = category_data[sub_key]
                    if isinstance(sub_questions, list):
                        print(f"        • {sub_key}: {len(sub_questions)} 题")
                if len(sub_categories) > 3:
                    print(f"        ... 还有 {len(sub_categories) - 3} 个子分类")
            print()
    
    print("=" * 70)
    return category_stats, data


def extract_all_questions(data):
    """提取所有题目，生成题目ID到分类的映射"""
    question_mapping = {}  # {question_id: category_key}
    question_counter = 1  # 用于生成题目ID
    
    for category_key, category_data in data.items():
        if isinstance(category_data, dict):
            for sub_key, questions in category_data.items():
                if isinstance(questions, list):
                    for question in questions:
                        # 生成题目ID（基于分类和索引）
                        # 注意：这里使用的是生成的ID，实际可能需要根据题目内容匹配
                        question_id = str(question_counter)
                        question_mapping[question_id] = {
                            'category': category_key,
                            'sub_category': sub_key,
                            'question': question.get('q', ''),
                            'img': question.get('img', ''),
                            'answer': question.get('a', False)
                        }
                        question_counter += 1
    
    return question_mapping


if __name__ == '__main__':
    json_path = '/Users/fabio/Desktop/patente/quizPatenteB2023.json'
    
    if not os.path.exists(json_path):
        print(f"❌ 文件不存在: {json_path}")
        sys.exit(1)
    
    # 分析结构
    category_stats, data = analyze_json_structure(json_path)
    
    # 提取题目
    print("\n正在提取题目...")
    question_mapping = extract_all_questions(data)
    print(f"✅ 总共提取 {len(question_mapping)} 道题目")
    
    # 保存分类列表到文件
    output_file = os.path.join(os.path.dirname(__file__), 'json_categories_list.txt')
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("JSON文件中的分类列表:\n")
        f.write("=" * 70 + "\n\n")
        for i, cat_key in enumerate(category_stats.keys(), 1):
            stats = category_stats[cat_key]
            f.write(f"{i}. {cat_key}\n")
            f.write(f"   子分类数: {stats['sub_categories']}\n")
            f.write(f"   题目数: {stats['total_questions']}\n\n")
    
    print(f"\n✅ 分类列表已保存到: {output_file}")
    print("\n下一步：需要创建这些分类到25个章节的映射关系")

