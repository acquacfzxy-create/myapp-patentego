#!/bin/bash
# 快速检查脚本状态

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="$SCRIPT_DIR/../../assets/italy_quiz.db"

echo "📊 脚本运行状态检查"
echo "===================="
echo ""

# 检查进程
if pgrep -f "generate_global_explanations.py" > /dev/null; then
    PID=$(pgrep -f "generate_global_explanations.py" | head -1)
    echo "✅ 脚本正在运行 (PID: $PID)"
else
    echo "❌ 脚本未运行"
    exit 1
fi

echo ""

# 检查数据库进度
if [ -f "$DB_PATH" ]; then
    sqlite3 "$DB_PATH" <<EOF
.mode column
.headers on
SELECT
  '已完成' as status,
  COUNT(*) as questions,
  ROUND(COUNT(*) * 100.0 / 7139, 2) || '%' as progress
FROM (
  SELECT question_id
  FROM translations
  WHERE type = 'e'
    AND lang IN ('zh', 'en', 'ru', 'uk', 'pa', 'ur')
    AND content LIKE '{%'
  GROUP BY question_id
  HAVING COUNT(DISTINCT lang) = 6
);
EOF
    echo ""
    echo "剩余题目: $((7139 - $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM (SELECT question_id FROM translations WHERE type = 'e' AND lang IN ('zh', 'en', 'ru', 'uk', 'pa', 'ur') AND content LIKE '{%' GROUP BY question_id HAVING COUNT(DISTINCT lang) = 6);")))"
fi

echo ""
echo "💡 查看实时日志: tail -f $SCRIPT_DIR/generate_explanations.log"
