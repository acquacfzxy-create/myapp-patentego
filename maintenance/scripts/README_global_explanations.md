# 多语言结构化题目解析生成脚本

## 功能说明

本脚本使用 Google Gemini 1.5 Pro API 批量生成多语言结构化题目解析，支持以下语言：
- zh (简体中文)
- en (英文)
- ru (俄语)
- uk (乌克兰语)
- pa (旁遮普语)
- ur (乌尔都语)

## 安装依赖

```bash
pip install google-generativeai retrying
```

## 运行脚本

```bash
cd scripts
python3 generate_global_explanations.py
```

或者直接运行：

```bash
python3 scripts/generate_global_explanations.py
```

## 脚本功能

1. **断点续传**：自动检查 `translations` 表中 `type='e'` 的记录，只处理缺失的解析
2. **批量处理**：每批处理 5 题（可配置），节省 Token
3. **重试机制**：使用 `retrying` 库，自动重试失败的请求（最多 3 次）
4. **速率控制**：每个请求之间延迟 2 秒，避免 API 限流
5. **数据验证**：验证 Gemini 返回的 JSON 格式，确保包含所有必需字段
6. **进度显示**：实时显示处理进度和统计信息

## 输出格式

生成的解析数据存储在 `translations` 表中，格式如下：

```json
{
  "detailed_description": "详细说明文本...",
  "key_points": [
    {"title": "Moderare la velocità", "content": "任何危险标志前的通用义务。"},
    {"title": "E' necessario", "content": "指法律上的"有必要"或"必须"。"}
  ],
  "study_tip": "遇到 "pericolo"（危险）相关的描述，通常伴随 "moderare" 或 "ridurre"（降低）速度的要求，这类题目绝大多数为 Vero。"
}
```

## 注意事项

1. **API Key**：脚本中已硬编码 API Key，请确保安全
2. **Token 消耗**：每道题目需要生成 6 种语言的解析，Token 消耗较大
3. **处理时间**：根据题目数量，处理时间可能较长（每道题约 2-3 秒）
4. **数据库备份**：建议在运行前备份数据库

## 配置参数

可以在脚本中修改以下参数：

- `BATCH_SIZE`: 每批处理的题目数量（默认：5）
- `DELAY_BETWEEN_REQUESTS`: 请求间隔（默认：2 秒）
- `MAX_RETRIES`: 最大重试次数（默认：3）
- `TARGET_LANGUAGES`: 目标语言列表
