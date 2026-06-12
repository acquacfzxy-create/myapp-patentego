#!/usr/bin/env python3
"""测试 Gemini API 连接和可用 Flash 模型。"""

import os

import google.generativeai as genai

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    raise SystemExit("请先设置环境变量 GEMINI_API_KEY")

# 配置 Gemini API
genai.configure(api_key=GEMINI_API_KEY)

# 列出所有可用的模型
print("🔍 正在列出所有可用的模型...")
try:
    models = genai.list_models()
    print("\n✅ 可用模型列表:")
    for model in models:
        if 'generateContent' in model.supported_generation_methods:
            print(f"  - {model.name}")
except Exception as e:
    print(f"❌ 错误: {e}")

# 尝试使用低成本 Flash 模型，避免误用 Pro
print("\n🔍 尝试使用 Flash 模型进行测试...")
model_candidates = (
    "gemini-1.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-2.5-flash",
    "gemini-2.0-flash",
)
for model_name in model_candidates:
    try:
        model = genai.GenerativeModel(model_name)
        response = model.generate_content(
            "Reply with only: test successful"
        )
        print(f"✅ {model_name} 测试成功: {response.text}")
        break
    except Exception as e:
        print(f"⚠️  {model_name} 测试失败: {e}")
else:
    print("❌ 所有 Flash 候选模型均测试失败")
