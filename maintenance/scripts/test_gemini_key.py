#!/usr/bin/env python3
"""快速验证 Gemini API Key 是否有效（只从环境变量读取）。"""
import os
import sys

API_KEY = os.environ.get("GEMINI_API_KEY")

def main():
    try:
        from google import genai
    except ImportError:
        print("❌ 請先安裝: pip install google-genai")
        sys.exit(1)

    if not API_KEY:
        print("❌ 请先设置环境变量 GEMINI_API_KEY")
        sys.exit(1)

    client = genai.Client(api_key=API_KEY)
    print("📡 正在調用 gemini-2.0-flash 測試...")
    try:
        r = client.models.generate_content(model="gemini-2.0-flash", contents="Reply with only: OK")
        text = (r.text or "").strip()
        print("✅ API 正常，模型回覆:", text[:80] if text else "(空)")
    except Exception as e:
        print("❌ 調用失敗:", e)
        if "401" in str(e) or "invalid" in str(e).lower() or "API key" in str(e):
            print("   → 很可能是 API Key 無效或已撤銷，請到 https://aistudio.google.com/apikey 檢查或重新生成。")
        elif "403" in str(e) or "quota" in str(e).lower():
            print("   → 可能是權限或配額問題，請檢查 Google Cloud 計費與 API 啟用狀態。")
        sys.exit(1)

if __name__ == "__main__":
    main()
