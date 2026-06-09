#!/usr/bin/env python3
"""
使用 Google Gemini API (1.5 Flash) 自动生成题目关键词解析
批量处理 italy_quiz.db 数据库中的所有题目
"""

import sqlite3
import json
import time
import os
import sys
from typing import List, Dict, Optional
from pathlib import Path

# 尝试导入 google-generativeai，如果失败则给出提示
try:
    import google.generativeai as genai
except ImportError:
    print("❌ 错误：未安装 google-generativeai 库")
    print("请运行: pip install google-generativeai")
    sys.exit(1)

# 配置
# 🔍 強制修復：使用絕對路徑，確保指向正確的數據庫文件
SCRIPT_DIR = Path(__file__).parent.absolute()
PROJECT_ROOT = SCRIPT_DIR.parent.parent.absolute()
DATABASE_PATH = PROJECT_ROOT / "assets" / "italy_quiz.db"

# 如果相對路徑不存在，嘗試絕對路徑
if not DATABASE_PATH.exists():
    print(f"❌ 错误：数据库文件不存在: {DATABASE_PATH}")
    sys.exit(1)

print(f"🔍 [Config] 腳本目錄: {SCRIPT_DIR}")
print(f"🔍 [Config] 項目根目錄: {PROJECT_ROOT}")
print(f"🔍 [Config] 數據庫路徑: {DATABASE_PATH}")
print(f"🔍 [Config] 數據庫文件存在: {DATABASE_PATH.exists()}")

BATCH_SIZE = 50  # 每批处理的题目数量
DELAY_BETWEEN_BATCHES = 5  # 批次之间的延迟（秒）- 增加到5秒以避免429错误
DELAY_BETWEEN_REQUESTS = 4  # 单个请求之间的延迟（秒）- 增加到4秒，确保不超过每分钟15次请求的限制
MAX_REQUESTS_PER_MINUTE = 12  # 每分钟最大请求数（保守设置，避免429错误）

# Gemini API 配置：只从环境变量读取
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
if not GEMINI_API_KEY:
    print("⚠️  警告：GEMINI_API_KEY 未设置")
    print("请通过环境变量提供 GEMINI_API_KEY，不要写入脚本或仓库文件。")
    sys.exit(1)


def init_gemini_client(api_key: str):
    """初始化 Gemini API 客户端"""
    genai.configure(api_key=api_key)
    # 使用 gemini-2.0-flash 模型（免费且快速，最新的 Flash 版本）
    # 如果不可用，可以尝试 'gemini-flash-latest' 或 'gemini-2.5-flash'
    model = genai.GenerativeModel('gemini-2.0-flash')
    return model


def get_questions_batch(
    conn: sqlite3.Connection,
    batch_size: int,
    offset: int,
    skip_existing: bool = True,
    force_update: bool = False
) -> List[Dict]:
    """
    从数据库获取一批题目

    Args:
        conn: 数据库连接
        batch_size: 批次大小
        offset: 偏移量（已处理的题目数量，用于进度显示）
        skip_existing: 是否跳过已有 keywords_json 的题目
        force_update: 是否强制更新所有题目（覆盖旧数据）

    Returns:
        题目列表，每个题目包含 id, question (意语正文)
    """
    cursor = conn.cursor()

    if force_update:
        # 强制更新模式：处理所有题目，包括已有 keywords_json 的
        query = """
            SELECT q.id, t.content as question
            FROM questions q
            LEFT JOIN translations t ON q.id = t.question_id AND t.lang = 'it' AND t.type = 'q'
            WHERE t.content IS NOT NULL
            ORDER BY CAST(q.id AS INTEGER)
            LIMIT ? OFFSET ?
        """
        cursor.execute(query, (batch_size, offset))
    elif skip_existing:
        # 🔍 修复：不使用 OFFSET，而是直接查询所有缺失的题目，然后取前 batch_size 个
        # 这样可以避免因为题目被更新导致 offset 不准确的问题
        # 同时检查是否包含所有必需的语言（如果只有部分语言，也需要更新）
        query = """
            SELECT q.id, t.content as question
            FROM questions q
            LEFT JOIN translations t ON q.id = t.question_id AND t.lang = 'it' AND t.type = 'q'
            WHERE (
                q.keywords_json IS NULL
                OR q.keywords_json = ''
                OR q.keywords_json = '[]'
                OR q.keywords_json NOT LIKE '%"en"%'
                OR q.keywords_json NOT LIKE '%"ru"%'
                OR q.keywords_json NOT LIKE '%"uk"%'
                OR q.keywords_json NOT LIKE '%"pa"%'
                OR q.keywords_json NOT LIKE '%"ur"%'
            )
            AND t.content IS NOT NULL
            ORDER BY CAST(q.id AS INTEGER)
            LIMIT ?
        """
        cursor.execute(query, (batch_size,))
    else:
        # 获取所有题目（用于测试）
        query = """
            SELECT q.id, t.content as question
            FROM questions q
            LEFT JOIN translations t ON q.id = t.question_id AND t.lang = 'it' AND t.type = 'q'
            WHERE t.content IS NOT NULL
            ORDER BY CAST(q.id AS INTEGER)
            LIMIT ? OFFSET ?
        """
        cursor.execute(query, (batch_size, offset))

    rows = cursor.fetchall()

    return [{"id": row[0], "question": row[1]} for row in rows]


def check_and_add_keywords_column(conn: sqlite3.Connection) -> bool:
    """检查并添加 keywords_json 字段（如果不存在）"""
    try:
        cursor = conn.cursor()

        # 检查字段是否存在
        cursor.execute("PRAGMA table_info(questions)")
        columns = [row[1] for row in cursor.fetchall()]

        if 'keywords_json' not in columns:
            print("📝 [Migration] 检测到 questions 表缺少 keywords_json 字段，开始添加...")
            cursor.execute("ALTER TABLE questions ADD COLUMN keywords_json TEXT")
            conn.commit()
            print("✅ [Migration] keywords_json 字段添加成功")
            return True
        else:
            print("ℹ️  [Migration] keywords_json 字段已存在")
            return False
    except Exception as e:
        print(f"⚠️  [Migration] 检查/添加 keywords_json 字段失败: {e}")
        conn.rollback()
        return False


def count_remaining_questions(conn: sqlite3.Connection, force_update: bool = False) -> int:
    """统计还需要处理的题目数量"""
    cursor = conn.cursor()

    # 只统计有意大利语题目的记录（JOIN translations 表）
    try:
        if force_update:
            # 强制更新模式：统计所有题目
            cursor.execute("""
                SELECT COUNT(*)
                FROM questions q
                LEFT JOIN translations t ON q.id = t.question_id AND t.lang = 'it' AND t.type = 'q'
                WHERE t.content IS NOT NULL
            """)
        else:
            # 统计需要更新的题目（包括缺失或缺少语言的）
            cursor.execute("""
                SELECT COUNT(*)
                FROM questions q
                LEFT JOIN translations t ON q.id = t.question_id AND t.lang = 'it' AND t.type = 'q'
                WHERE (
                    q.keywords_json IS NULL
                    OR q.keywords_json = ''
                    OR q.keywords_json = '[]'
                    OR q.keywords_json NOT LIKE '%"en"%'
                    OR q.keywords_json NOT LIKE '%"ru"%'
                    OR q.keywords_json NOT LIKE '%"uk"%'
                    OR q.keywords_json NOT LIKE '%"pa"%'
                    OR q.keywords_json NOT LIKE '%"ur"%'
                )
                AND t.content IS NOT NULL
            """)
        return cursor.fetchone()[0]
    except sqlite3.OperationalError as e:
        # 如果字段不存在或其他错误，尝试简单查询
        print(f"⚠️  统计题目数量时出错: {e}")
        try:
            cursor.execute("SELECT COUNT(*) FROM questions")
            return cursor.fetchone()[0]
        except:
            return 0


def generate_keywords_prompt(question_text: str) -> str:
    """生成发送给 Gemini 的提示词（支持全语种翻译）"""
    prompt = f"""你是一个意大利驾照考试专家。请分析以下意大利语题目，提取 1-3 个对理解题目至关重要的重点单词或短语。

题目：
{question_text}

要求（必须严格遵守）：
1. **强制要求：** 即使题目简短，也必须提取至少 1-2 个交通术语或关键词。严禁返回空列表 []。
2. 优先提取交通相关的专业术语（如：carreggiata、banchina、sorpasso、incrocio、semaforo 等）
3. **多语言翻译：** 必须为每个关键词提供以下所有语言的准确翻译：
   - 中文 (zh)
   - 英文 (en)
   - 俄语 (ru)
   - 乌克兰语 (uk)
   - 旁遮普语 (pa)
   - 乌尔都语 (ur)
4. 返回纯 JSON 格式，不使用 Markdown 代码块
5. **JSON 格式（必须包含所有语言）：** [{{"it": "意大利语单词", "zh": "中文翻译", "en": "英文翻译", "ru": "俄语翻译", "uk": "乌克兰语翻译", "pa": "旁遮普语翻译", "ur": "乌尔都语翻译"}}]
6. **重要：** 如果题目中确实没有明显的交通术语，请提取题目中的核心词汇（如：vietato、obbligatorio、consentito 等）
7. **翻译质量：** 确保所有语言的翻译都是准确的，特别是交通术语的专业翻译

只返回 JSON 数组，不要其他内容。严禁返回空数组。每个对象必须包含所有 7 种语言的翻译："""

    return prompt


def call_gemini_api(
    model,
    question_text: str,
    max_retries: int = 3
) -> Optional[List[Dict[str, str]]]:
    """
    调用 Gemini API 生成关键词

    Args:
        model: Gemini 模型实例
        question_text: 题目文本（意大利语）
        max_retries: 最大重试次数

    Returns:
        关键词列表，格式：[{"it": "...", "zh": "..."}]
        如果失败返回 None
    """
    prompt = generate_keywords_prompt(question_text)

    for attempt in range(max_retries):
        try:
            response = model.generate_content(prompt)
            response_text = response.text.strip()

            # 清理响应文本（移除可能的 Markdown 代码块标记）
            if response_text.startswith("```json"):
                response_text = response_text[7:]
            if response_text.startswith("```"):
                response_text = response_text[3:]
            if response_text.endswith("```"):
                response_text = response_text[:-3]
            response_text = response_text.strip()

            # 解析 JSON
            keywords = json.loads(response_text)

            # 验证格式
            if not isinstance(keywords, list):
                print(f"    ⚠️  警告：返回的不是列表格式，跳过")
                return None

            # 验证每个元素是否包含所有必需的语言
            # 必需语言：it, zh, en, ru, uk, pa, ur
            required_languages = ['it', 'zh', 'en', 'ru', 'uk', 'pa', 'ur']
            validated_keywords = []

            for item in keywords:
                if isinstance(item, dict):
                    # 检查是否包含所有必需的语言
                    has_all_languages = all(lang in item for lang in required_languages)

                    if has_all_languages:
                        # 构建包含所有语言的字典
                        keyword_dict = {}
                        for lang in required_languages:
                            keyword_dict[lang] = str(item[lang]) if item[lang] else ''
                        validated_keywords.append(keyword_dict)
                    else:
                        # 如果缺少某些语言，打印警告但继续处理（向后兼容）
                        missing_langs = [lang for lang in required_languages if lang not in item]
                        if 'it' in item and 'zh' in item:
                            # 向后兼容：如果只有 it 和 zh，也接受（但会标记为不完整）
                            keyword_dict = {}
                            for lang in required_languages:
                                keyword_dict[lang] = str(item.get(lang, ''))
                            validated_keywords.append(keyword_dict)
                            if missing_langs:
                                print(f"    ⚠️  警告：关键词缺少语言: {missing_langs}，已使用空字符串填充")

            if not validated_keywords:
                print(f"    ⚠️  警告：没有有效的关键词（必须包含 it, zh, en, ru, uk, pa, ur），跳过")
                return None

            return validated_keywords

        except json.JSONDecodeError as e:
            print(f"    ⚠️  JSON 解析失败 (尝试 {attempt + 1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                time.sleep(2)  # 重试前等待
            else:
                print(f"    ❌ 最终失败：无法解析 JSON 响应")
                print(f"    响应内容: {response_text[:200]}")
                return None

        except Exception as e:
            error_str = str(e)
            print(f"    ⚠️  API 调用失败 (尝试 {attempt + 1}/{max_retries}): {e}")

            # 如果是429错误（速率限制），等待更长时间
            if '429' in error_str or 'rate limit' in error_str.lower() or 'quota' in error_str.lower():
                wait_time = (attempt + 1) * 10  # 429错误时等待更长时间：10秒、20秒、30秒
                print(f"    ⏸️  检测到速率限制，等待 {wait_time} 秒后重试...")
                time.sleep(wait_time)
            elif attempt < max_retries - 1:
                time.sleep(5)  # 其他错误等待5秒
            else:
                print(f"    ❌ 最终失败：{e}")
                return None

    return None


def update_question_keywords(
    conn: sqlite3.Connection,
    question_id: str,
    keywords: List[Dict[str, str]]
) -> bool:
    """更新题目的 keywords_json 字段"""
    try:
        keywords_json = json.dumps(keywords, ensure_ascii=False)
        cursor = conn.cursor()

        # 🔍 強力調試：打印更新前的狀態
        cursor.execute("SELECT keywords_json FROM questions WHERE id = ?", (question_id,))
        old_value = cursor.fetchone()
        print(f"    🔍 [Update] 更新前 keywords_json: {old_value[0] if old_value else 'None'}")

        # 執行更新
        cursor.execute(
            "UPDATE questions SET keywords_json = ? WHERE id = ?",
            (keywords_json, question_id)
        )

        # 🔍 強力調試：驗證更新是否成功
        conn.commit()
        cursor.execute("SELECT keywords_json FROM questions WHERE id = ?", (question_id,))
        new_value = cursor.fetchone()
        if new_value and new_value[0] == keywords_json:
            print(f"    ✅ [Update] 更新成功，新值長度: {len(keywords_json)}")
            return True
        else:
            print(f"    ⚠️  [Update] 更新後驗證失敗！")
            print(f"    🔍 [Update] 期望值: {keywords_json[:100]}...")
            print(f"    🔍 [Update] 實際值: {new_value[0][:100] if new_value and new_value[0] else 'None'}...")
            return False
    except Exception as e:
        print(f"    ❌ 更新数据库失败: {e}")
        import traceback
        traceback.print_exc()
        conn.rollback()
        return False


def main():
    """主函数"""
    print("🚀 开始使用 Gemini API 生成关键词解析（全语种支持）")
    print(f"📁 数据库路径: {DATABASE_PATH}")
    print(f"📊 批次大小: {BATCH_SIZE}")
    print(f"⏱️  批次延迟: {DELAY_BETWEEN_BATCHES} 秒")
    print(f"⏱️  请求延迟: {DELAY_BETWEEN_REQUESTS} 秒")
    print("🌍 支持语言: it, zh, en, ru, uk, pa, ur")
    print("-" * 60)

    # 检查数据库文件是否存在
    if not DATABASE_PATH.exists():
        print(f"❌ 错误：数据库文件不存在: {DATABASE_PATH}")
        sys.exit(1)

    # 询问是否强制更新所有题目
    print("\n❓ 是否强制更新所有题目（覆盖旧数据）？")
    print("   - 输入 'y' 或 'yes'：强制更新所有 7139 道题")
    print("   - 输入其他或直接回车：只更新缺失或缺少语言的题目")
    force_update_input = input("   请选择: ").strip().lower()
    force_update = force_update_input in ['y', 'yes']

    if force_update:
        print("⚠️  已启用强制更新模式：将覆盖所有现有数据")
    else:
        print("ℹ️  使用增量更新模式：只更新缺失或缺少语言的题目")

    # 初始化 Gemini API
    print("\n🔧 初始化 Gemini API 客户端...")
    try:
        model = init_gemini_client(GEMINI_API_KEY)
        print("✅ Gemini API 客户端初始化成功")
    except Exception as e:
        print(f"❌ Gemini API 初始化失败: {e}")
        sys.exit(1)

    # 连接数据库
    print("🔌 连接数据库...")
    try:
        conn = sqlite3.connect(DATABASE_PATH)
        conn.row_factory = sqlite3.Row
        print("✅ 数据库连接成功")
    except Exception as e:
        print(f"❌ 数据库连接失败: {e}")
        sys.exit(1)

    # 检查并添加 keywords_json 字段（如果不存在）
    print("🔍 检查数据库结构...")
    check_and_add_keywords_column(conn)

    # 统计需要处理的题目数量
    total_remaining = count_remaining_questions(conn, force_update=force_update)
    print(f"📊 待处理题目数量: {total_remaining}")

    if total_remaining == 0:
        print("✅ 所有题目都已处理完成！")
        conn.close()
        return

    # 批量处理
    batch_number = 0
    total_processed = 0
    total_success = 0
    total_failed = 0

    print("-" * 60)
    print("🔄 开始批量处理...")
    print("-" * 60)

    try:
        offset = 0
        while True:
            # 🔍 修复：每次都重新查询缺失的题目，不使用 offset（除非强制更新模式）
            # 这样可以确保即使题目被更新，也能继续处理剩余的题目
            if force_update:
                questions = get_questions_batch(conn, BATCH_SIZE, offset, skip_existing=False, force_update=True)
                offset += len(questions)
            else:
                questions = get_questions_batch(conn, BATCH_SIZE, 0, skip_existing=True, force_update=False)

            if not questions:
                print("✅ 所有题目处理完成！")
                break

            batch_number += 1
            batch_start_time = time.time()

            print(f"\n📦 批次 #{batch_number} - 处理 {len(questions)} 道题目")
            print(f"   📍 已处理总数: {total_processed}")

            batch_success = 0
            batch_failed = 0

            # 处理批次中的每道题目
            request_count = 0  # 跟踪每分钟的请求数
            minute_start_time = time.time()

            for idx, question in enumerate(questions, 1):
                question_id = question['id']
                question_text = question['question']

                print(f"   [{idx}/{len(questions)}] 题目 ID: {question_id}", end=" ... ")

                # 检查速率限制：如果这分钟内已经发送了太多请求，等待
                current_time = time.time()
                elapsed_seconds = current_time - minute_start_time
                if request_count >= MAX_REQUESTS_PER_MINUTE and elapsed_seconds < 60:
                    wait_seconds = 60 - elapsed_seconds + 2  # 等待到下一分钟，额外2秒缓冲
                    print(f"\n   ⏸️  速率限制：已发送 {request_count} 个请求，等待 {wait_seconds:.1f} 秒...")
                    time.sleep(wait_seconds)
                    request_count = 0
                    minute_start_time = time.time()
                elif elapsed_seconds >= 60:
                    # 新的一分钟，重置计数器
                    request_count = 0
                    minute_start_time = time.time()

                # 调用 Gemini API
                keywords = call_gemini_api(model, question_text)
                request_count += 1

                if keywords:
                    # 验证关键词不为空
                    if len(keywords) == 0:
                        print(f"⚠️  警告：返回空列表，跳过")
                        batch_failed += 1
                        total_failed += 1
                    else:
                        # 更新数据库
                        if update_question_keywords(conn, question_id, keywords):
                            print(f"✅ 成功 ({len(keywords)} 个关键词)")
                            batch_success += 1
                            total_success += 1
                        else:
                            print(f"❌ 数据库更新失败")
                            batch_failed += 1
                            total_failed += 1
                else:
                    print(f"❌ API 调用失败")
                    batch_failed += 1
                    total_failed += 1

                total_processed += 1

                # 请求之间延迟（确保不超过速率限制）
                if idx < len(questions):
                    time.sleep(DELAY_BETWEEN_REQUESTS)

            # 批次统计
            batch_time = time.time() - batch_start_time
            print(f"\n   📊 批次统计: 成功 {batch_success}, 失败 {batch_failed}, 耗时 {batch_time:.1f} 秒")

            # 🔍 修复：重新统计剩余题目数量，用于显示准确的进度
            remaining = count_remaining_questions(conn, force_update=force_update)
            progress = ((total_remaining - remaining) / total_remaining) * 100 if total_remaining > 0 else 0
            print(f"   📈 整体进度: {total_remaining - remaining}/{total_remaining} ({progress:.1f}%)")
            print(f"   ✅ 总计成功: {total_success}, ❌ 总计失败: {total_failed}")
            print(f"   📊 剩余题目: {remaining}")

            # 批次之间延迟
            if questions:  # 如果还有题目，则延迟
                print(f"   ⏸️  等待 {DELAY_BETWEEN_BATCHES} 秒后继续下一批次...")
                time.sleep(DELAY_BETWEEN_BATCHES)

    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断")
        print(f"📊 已处理: {total_processed}/{total_remaining}")
        print(f"✅ 成功: {total_success}, ❌ 失败: {total_failed}")
        print("💾 已保存进度，可以稍后重新运行脚本继续处理")

    except Exception as e:
        print(f"\n❌ 发生错误: {e}")
        import traceback
        traceback.print_exc()

    finally:
        conn.close()
        print("\n✅ 数据库连接已关闭")
        print("🎉 处理完成！")


if __name__ == "__main__":
    main()
