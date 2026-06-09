#!/bin/bash
# 自动运行解析生成脚本（后台模式）

cd "$(dirname "$0")"
LOG_FILE="generate_explanations.log"
PID_FILE="generate_explanations.pid"

echo "🚀 启动自动解析生成脚本..."
echo "📝 日志文件: $LOG_FILE"
echo "🆔 PID 文件: $PID_FILE"
echo ""

# 启动脚本
nohup python3 generate_global_explanations.py > "$LOG_FILE" 2>&1 &
PID=$!

# 保存 PID
echo $PID > "$PID_FILE"
echo "✅ 脚本已启动，PID: $PID"
echo ""
echo "📊 查看实时日志: tail -f $LOG_FILE"
echo "🛑 停止脚本: kill $PID"
echo ""
echo "脚本正在后台运行，处理所有题目..."
