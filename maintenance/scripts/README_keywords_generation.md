# 关键词自动生成脚本使用说明

使用 Google Gemini API (1.5 Flash) 自动生成全库题目的关键词解析。

## 📋 前置要求

1. **Python 3.7+**
2. **Google Gemini API Key**
   - 访问 [Google AI Studio](https://makersuite.google.com/app/apikey) 获取免费 API Key
   - Gemini 1.5 Flash 免费版有 Rate Limit，请合理设置延迟

## 📦 安装依赖

### macOS/Linux 用户

```bash
# 方法 1：使用 python3 -m pip（推荐）
python3 -m pip install google-generativeai

# 方法 2：使用 pip3
pip3 install google-generativeai

# 或者使用 requirements.txt
python3 -m pip install -r requirements_keywords.txt
```

### Windows 用户

```bash
# 使用 pip
pip install google-generativeai

# 或者使用 python -m pip
python -m pip install google-generativeai
```

### 依赖说明

- `google-generativeai`: Google Gemini API 客户端库
- `sqlite3`: Python 标准库，无需安装

**注意：** 如果遇到 `pip: command not found` 错误，请使用 `python3 -m pip` 或 `pip3` 代替 `pip`。

## 🔑 设置 API Key

### 方法 1：环境变量（推荐）

```bash
# Linux/macOS、Windows PowerShell 或 CMD
# 请在本机 shell 中设置 GEMINI_API_KEY 环境变量
```

不要把 API key 直接写进脚本或仓库文件；只使用环境变量。

## 🚀 运行脚本

```bash
# 确保在项目根目录下运行
cd /path/to/assets

# 运行脚本
python3 maintenance/scripts/generate_keywords_with_gemini.py
```

## ⚙️ 配置选项

可以在脚本中调整以下参数：

```python
BATCH_SIZE = 50              # 每批处理的题目数量（默认：50）
DELAY_BETWEEN_BATCHES = 2    # 批次之间的延迟（秒，默认：2）
DELAY_BETWEEN_REQUESTS = 1   # 单个请求之间的延迟（秒，默认：1）
```

**注意：** 根据你的 API 配额和 Rate Limit，可能需要调整这些参数。

## 📊 功能特性

### ✅ 断点续传
- 自动跳过已有 `keywords_json` 的题目
- 脚本中断后可以重新运行，从中断点继续

### ✅ 批量处理
- 每批处理 50 道题目
- 可配置批次大小和延迟时间

### ✅ 错误处理
- 自动重试失败的请求（最多 3 次）
- 详细的错误日志输出
- 失败的题目不影响其他题目的处理

### ✅ 进度追踪
- 实时显示处理进度
- 批次统计和整体统计
- 成功/失败数量统计

## 📝 输出格式

脚本会将关键词解析保存为 JSON 格式：

```json
[
  {"it": "Carreggiata", "zh": "行车道"},
  {"it": "Banchina", "zh": "路肩"}
]
```

## 🔍 验证结果

处理完成后，可以验证数据库中的关键词数据：

```bash
# 使用 SQLite 命令行工具
sqlite3 assets/italy_quiz.db

# 查看有关键词的题目数量
SELECT COUNT(*) FROM questions WHERE keywords_json IS NOT NULL AND keywords_json != '' AND keywords_json != '[]';

# 查看前 5 题的关键词
SELECT id, keywords_json FROM questions WHERE keywords_json IS NOT NULL AND keywords_json != '' AND keywords_json != '[]' LIMIT 5;
```

## ⚠️ 注意事项

1. **API 配额限制**
   - Gemini 1.5 Flash 免费版有 Rate Limit
   - 如果遇到 Rate Limit 错误，请增加延迟时间
   - 建议在非高峰时段运行脚本

2. **数据备份**
   - 运行前建议备份数据库
   - 脚本会直接修改数据库，请谨慎操作

3. **网络连接**
   - 需要稳定的网络连接
   - 如果网络不稳定，可能需要多次运行脚本

4. **处理时间**
   - 全库 7139 题，按每批 50 题，每批延迟 2 秒计算
   - 预计需要约 4-6 小时（取决于网络和 API 响应速度）

## 🐛 故障排除

### 问题 1：API Key 未设置
```
错误：GEMINI_API_KEY 未设置
```
**解决方案：** 按照“设置 API Key”部分的说明设置环境变量或修改脚本。

### 问题 2：Rate Limit 错误
```
错误：429 Too Many Requests
```
**解决方案：** 增加 `DELAY_BETWEEN_BATCHES` 和 `DELAY_BETWEEN_REQUESTS` 的值。

### 问题 3：数据库文件不存在
```
错误：数据库文件不存在
```
**解决方案：** 确保 `assets/italy_quiz.db` 文件存在，或修改脚本中的 `DATABASE_PATH`。

### 问题 4：JSON 解析失败
```
警告：JSON 解析失败
```
**解决方案：** 这是正常的，脚本会自动重试。如果持续失败，可能是 Gemini API 返回格式异常，可以手动检查并调整 prompt。

## 📚 参考资料

- [Google Gemini API 文档](https://ai.google.dev/docs)
- [google-generativeai Python 库](https://github.com/google/generative-ai-python)
