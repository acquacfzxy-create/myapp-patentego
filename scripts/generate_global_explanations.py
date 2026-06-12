#!/usr/bin/env python3
"""
入口轉發：實際腳本位於 maintenance/scripts/generate_global_explanations.py
用法範例：
  先在本机 shell 中设置 GEMINI_API_KEY 环境变量
  python3 scripts/generate_global_explanations.py --only-wrong --force --limit 5
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
_TARGET = _ROOT / "maintenance" / "scripts" / "generate_global_explanations.py"

if __name__ == "__main__":
    if not _TARGET.is_file():
        print(f"❌ 找不到腳本: {_TARGET}")
        sys.exit(1)
    raise SystemExit(subprocess.call([sys.executable, str(_TARGET), *sys.argv[1:]]))
