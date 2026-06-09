#!/usr/bin/env python3
"""Resize assets/images/app_icon.png into AppIcon.appiconset per Contents.json (RGB, #3B82F6)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".python_packages"))

from PIL import Image  # noqa: E402

BG = (0x3B, 0x82, 0xF6)
CONTENTS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
SOURCE = ROOT / "assets/images/app_icon.png"
OUT_DIR = CONTENTS.parent


def pixel_size(size_str: str, scale_str: str) -> tuple[int, int]:
    parts = size_str.lower().replace(" ", "").split("x")
    if len(parts) != 2:
        raise ValueError(f"bad size: {size_str!r}")
    w_pt, h_pt = float(parts[0]), float(parts[1])
    mult = int(scale_str.replace("x", "").strip() or "1")
    w = max(1, int(round(w_pt * mult)))
    h = max(1, int(round(h_pt * mult)))
    return w, h


def flatten_on_blue(rgba: Image.Image, size: tuple[int, int]) -> Image.Image:
    w, h = size
    resized = rgba.resize((w, h), Image.Resampling.LANCZOS)
    base = Image.new("RGB", (w, h), BG)
    if resized.mode == "RGBA":
        base.paste(resized, (0, 0), resized.getchannel("A"))
    else:
        base.paste(resized.convert("RGB"), (0, 0))
    return base


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"missing source: {SOURCE}")
    if not CONTENTS.is_file():
        raise SystemExit(f"missing Contents.json: {CONTENTS}")

    with CONTENTS.open(encoding="utf-8") as f:
        data = json.load(f)

    src = Image.open(SOURCE).convert("RGBA")
    expected_filenames: set[str] = set()

    for entry in data.get("images", []):
        fn = entry.get("filename")
        if not fn:
            continue
        size_s = entry["size"]
        scale_s = entry["scale"]
        w, h = pixel_size(size_s, scale_s)
        out = flatten_on_blue(src, (w, h))
        out_path = OUT_DIR / fn
        out.save(out_path, "PNG")
        expected_filenames.add(fn)

    for p in OUT_DIR.glob("Icon-App-*.png"):
        if p.name not in expected_filenames:
            p.unlink()

    print(f"Wrote {len(expected_filenames)} icons into {OUT_DIR}")


if __name__ == "__main__":
    main()
