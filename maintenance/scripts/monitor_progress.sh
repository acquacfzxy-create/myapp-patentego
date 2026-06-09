#!/bin/bash
# 实时监控脚本运行状态

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/generate_explanations.log"
DB_PATH="$SCRIPT_DIR/../../assets/italy_quiz.db"

echo "📊 解析生成脚本实时监控"
echo "================================"
echo ""

# 检查日志文件
if [ ! -f "$LOG_FILE" ]; then
    echo "⚠️  日志文件不存在: $LOG_FILE"
    echo "💡 提示：脚本可能尚未启动"
    exit 1
fi

# 显示最新日志
echo "📝 最新日志（最后20行）："
echo "--------------------------------"
tail -20 "$LOG_FILE"
echo ""

# 检查数据库进度
if [ -f "$DB_PATH" ]; then
    echo "📊 数据库进度："
    echo "--------------------------------"
    sqlite3 "$DB_PATH" <<EOF
SELECT
  '总题目数: ' || (SELECT COUNT(*) FROM questions) as total,
  '已完成: ' || (
    SELECT COUNT(*)
    FROM (
      SELECT question_id
      FROM translations
      WHERE type = 'e'
        AND lang IN ('zh', 'en', 'ru', 'uk', 'pa', 'ur')
        AND content LIKE '{%'
      GROUP BY question_id
      HAVING COUNT(DISTINCT lang) = 6
    )
  ) as completed,
  '进度: ' || ROUND(
    (SELECT COUNT(*)
     FROM (
       SELECT question_id
       FROM translations
       WHERE type = 'e'
         AND lang IN ('zh', 'en', 'ru', 'uk', 'pa', 'ur')
         AND content LIKE '{%'
       GROUP BY question_id
       HAVING COUNT(DISTINCT lang) = 6
     )) * 100.0 / (SELECT COUNT(*) FROM questions),
    2
  ) || '%' as progress;
EOF
    echo ""
fi

echo "💡 实时监控命令："
echo "   tail -f $LOG_FILE"
echo ""
echo "🔄 刷新进度："
echo "   bash $0"
