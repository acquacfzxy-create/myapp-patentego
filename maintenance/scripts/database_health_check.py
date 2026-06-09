#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
数据库体检报告生成脚本
统计章节分配情况，检查数据完整性
"""

import sqlite3
import os
import sys
from typing import Dict, List, Tuple

# 数据库路径
DB_PATH = 'assets/italy_quiz.db'


def connect_database() -> sqlite3.Connection:
    """连接数据库"""
    if not os.path.exists(DB_PATH):
        print(f"❌ 数据库文件不存在: {DB_PATH}")
        sys.exit(1)

    try:
        db = sqlite3.connect(DB_PATH)
        return db
    except Exception as e:
        print(f"❌ 数据库连接失败: {e}")
        sys.exit(1)


def get_chapter_statistics(db: sqlite3.Connection) -> Dict[int, int]:
    """获取各章节的题目数量统计"""
    cursor = db.cursor()
    cursor.execute('''
        SELECT chapter, COUNT(*) as count
        FROM questions
        WHERE chapter IS NOT NULL AND chapter BETWEEN 1 AND 25
        GROUP BY chapter
        ORDER BY chapter
    ''')

    stats = {}
    for chapter_id, count in cursor.fetchall():
        stats[chapter_id] = count

    return stats


def get_unassigned_count(db: sqlite3.Connection) -> int:
    """获取未分配章节的题目数量（chapter IS NULL）"""
    cursor = db.cursor()
    cursor.execute('SELECT COUNT(*) FROM questions WHERE chapter IS NULL')
    return cursor.fetchone()[0]


def get_invalid_chapter_count(db: sqlite3.Connection) -> int:
    """获取章节编号无效的题目数量（不在 1-25 范围内）"""
    cursor = db.cursor()
    cursor.execute('SELECT COUNT(*) FROM questions WHERE chapter IS NOT NULL AND (chapter < 1 OR chapter > 25)')
    return cursor.fetchone()[0]


def get_total_count(db: sqlite3.Connection) -> int:
    """获取题目总数"""
    cursor = db.cursor()
    cursor.execute('SELECT COUNT(*) FROM questions')
    return cursor.fetchone()[0]


def get_status(count: int) -> str:
    """根据题目数量返回状态"""
    if count >= 100:
        return '✅ 充足'
    elif count >= 50:
        return '⚠️  一般'
    else:
        return '🔴 预警'


def format_table(stats: Dict[int, int]) -> List[Tuple[int, int, str]]:
    """格式化表格数据"""
    table_data = []
    for chapter_id in range(1, 26):
        count = stats.get(chapter_id, 0)
        status = get_status(count)
        table_data.append((chapter_id, count, status))
    return table_data


def print_report(db: sqlite3.Connection):
    """生成并打印体检报告"""
    print("=" * 80)
    print("📊 数据库体检报告")
    print("=" * 80)

    # 1. 章节统计
    print("\n【1. 章节题目数量统计】")
    print("-" * 80)
    stats = get_chapter_statistics(db)
    table_data = format_table(stats)

    # 打印表头
    print(f"{'章节编号':<10} {'题目数量':<12} {'状态':<15}")
    print("-" * 80)

    # 打印表格内容
    total_assigned = 0
    for chapter_id, count, status in table_data:
        total_assigned += count
        print(f"{chapter_id:<10} {count:<12} {status:<15}")

    print("-" * 80)
    print(f"{'合计':<10} {total_assigned:<12} {'':<15}")

    # 2. 总体统计
    print("\n【2. 总体统计】")
    print("-" * 80)
    total_count = get_total_count(db)
    unassigned_count = get_unassigned_count(db)
    invalid_count = get_invalid_chapter_count(db)

    print(f"题目总数:           {total_count:,}")
    print(f"已分配章节 (1-25):  {total_assigned:,}")
    print(f"未分配 (NULL):      {unassigned_count:,}")
    print(f"无效章节编号:       {invalid_count:,}")

    # 计算分配率
    if total_count > 0:
        assignment_rate = (total_assigned / total_count) * 100
        print(f"章节分配率:         {assignment_rate:.2f}%")

    # 3. 匹配验证
    print("\n【3. 匹配验证】")
    print("-" * 80)

    if unassigned_count > 0:
        print(f"⚠️  发现 {unassigned_count} 道题目未分配章节 (chapter IS NULL)")
        print("   这些题目可能是数据库中的额外题目，不在 JSON 文件中")
    else:
        print("✅ 所有题目都已分配章节")

    if invalid_count > 0:
        print(f"🔴 发现 {invalid_count} 道题目的章节编号无效（不在 1-25 范围内）")
        print("   请检查数据完整性")
    else:
        print("✅ 所有章节编号都在有效范围内 (1-25)")

    # 4. 章节覆盖情况
    print("\n【4. 章节覆盖情况】")
    print("-" * 80)

    missing_chapters = []
    for chapter_id in range(1, 26):
        if chapter_id not in stats:
            missing_chapters.append(chapter_id)

    if missing_chapters:
        print(f"⚠️  以下章节没有题目: {', '.join(map(str, missing_chapters))}")
    else:
        print("✅ 所有章节（1-25）都有题目")

    # 5. 章节分布分析
    print("\n【5. 章节分布分析】")
    print("-" * 80)

    counts = [count for count in stats.values()]
    if counts:
        max_count = max(counts)
        min_count = min(counts)
        avg_count = sum(counts) / len(counts)

        max_chapters = [ch for ch, cnt in stats.items() if cnt == max_count]
        min_chapters = [ch for ch, cnt in stats.items() if cnt == min_count]

        print(f"最多题目章节:       章节 {', '.join(map(str, max_chapters))} ({max_count} 题)")
        print(f"最少题目章节:       章节 {', '.join(map(str, min_chapters))} ({min_count} 题)")
        print(f"平均题目数量:       {avg_count:.1f} 题")

    # 6. 健康评分
    print("\n【6. 数据库健康评分】")
    print("-" * 80)

    score = 100
    issues = []

    # 检查未分配题目
    if unassigned_count > 0:
        penalty = min(unassigned_count / total_count * 50, 20)  # 最多扣20分
        score -= penalty
        issues.append(f"未分配题目 ({unassigned_count} 题)")

    # 检查无效章节
    if invalid_count > 0:
        score -= 30  # 无效章节严重问题
        issues.append(f"无效章节编号 ({invalid_count} 题)")

    # 检查缺失章节
    if missing_chapters:
        penalty = len(missing_chapters) * 2  # 每个缺失章节扣2分
        score -= penalty
        issues.append(f"缺失章节 ({len(missing_chapters)} 个)")

    # 检查题目数量过少的章节
    low_count_chapters = [ch for ch, cnt in stats.items() if cnt < 50]
    if low_count_chapters:
        penalty = len(low_count_chapters) * 1  # 每个预警章节扣1分
        score -= penalty
        issues.append(f"题目数量过少的章节 ({len(low_count_chapters)} 个)")

    score = max(0, score)  # 确保分数不为负

    if score >= 90:
        grade = "优秀"
        emoji = "🌟"
    elif score >= 75:
        grade = "良好"
        emoji = "✅"
    elif score >= 60:
        grade = "一般"
        emoji = "⚠️"
    else:
        grade = "需要改进"
        emoji = "🔴"

    print(f"{emoji} 健康评分: {score:.1f}/100 ({grade})")

    if issues:
        print("\n发现的问题:")
        for issue in issues:
            print(f"  • {issue}")
    else:
        print("\n✅ 数据库状态良好，未发现明显问题")

    print("\n" + "=" * 80)
    print("报告生成完成")
    print("=" * 80)


def main():
    """主函数"""
    print("🔍 正在生成数据库体检报告...\n")

    db = connect_database()
    try:
        print_report(db)
    finally:
        db.close()


if __name__ == '__main__':
    main()

