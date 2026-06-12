#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
只讀檢查 assets/ 圖片右下角是否存在疑似水印，輸出 watermark_report.txt。

依賴：
    pip install opencv-python numpy
"""

import os
import sys
from typing import List, Dict, Tuple

import cv2  # type: ignore
import numpy as np  # type: ignore


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))

# 圖片根目錄：實際題目圖片所在的 images 目錄
ASSETS_ROOT = os.path.join(PROJECT_ROOT, "images")
REPORT_PATH = os.path.join(PROJECT_ROOT, "maintenance", "reports", "watermark_report.txt")

# 支援的圖片副檔名
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".JPG", ".JPEG", ".PNG"}


def iter_image_files(root: str) -> List[str]:
  """遞迴遍歷 root 下所有圖片檔案路徑。"""
  results: List[str] = []
  for dirpath, _, filenames in os.walk(root):
    for name in filenames:
      _, ext = os.path.splitext(name)
      if ext in IMAGE_EXTS:
        results.append(os.path.join(dirpath, name))
  return sorted(results)


def detect_watermark_roi(
  image_path: str,
  roi_width_ratio: float = 0.25,
  roi_height_ratio: float = 0.15,
  edge_ratio_threshold: float = 0.06,
  stddev_threshold: float = 10.0,
) -> Tuple[bool, str]:
  """
  檢查單張圖片右下角 ROI 是否疑似存在水印。

  返回 (has_watermark, position_label)。
  position_label 用於統計水印大致集中在 ROI 內哪個位置。
  """
  img = cv2.imread(image_path, cv2.IMREAD_COLOR)
  if img is None:
    # 無法讀取圖片，視為無水印但打印提示
    print(f"[跳過] 無法讀取圖片: {image_path}")
    return False, "unreadable"

  h, w = img.shape[:2]
  if h < 10 or w < 10:
    return False, "too_small"

  # 右下角 ROI：略微內縮，避免紅色邊框之類的圖形干擾
  roi_w = max(1, int(w * roi_width_ratio))
  roi_h = max(1, int(h * roi_height_ratio))
  x1 = max(0, w - roi_w)
  y1 = max(0, h - roi_h)
  roi = img[y1:h, x1:w]

  gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)

  # 檢查該區域是否接近純白背景：
  # 1) 平均亮度要夠高（避免紅色邊框 / 彩色內容）
  # 2) 標準差很小則幾乎無內容
  mean, stddev = cv2.meanStdDev(gray)
  mean_val = float(mean[0][0])
  stddev_val = float(stddev[0][0])

  # 若本身就不是亮底（例如紅邊、彩色圖案），直接視為無水印，避免誤報
  if mean_val < 200.0:
    return False, "non_bright_bg"

  # 邊緣檢測：文字/線條會增加邊緣密度
  edges = cv2.Canny(gray, 100, 200)
  edge_pixels = int(np.count_nonzero(edges))
  total_pixels = edges.size
  edge_ratio = edge_pixels / float(total_pixels) if total_pixels > 0 else 0.0

  has_watermark = stddev_val > stddev_threshold and edge_ratio > edge_ratio_threshold

  position_label = "none"
  if has_watermark and edge_pixels > 0:
    ys, xs = np.where(edges > 0)
    # 計算邊緣像素的重心位置（歸一化到 ROI 內 0~1）
    cy = float(np.mean(ys)) / max(roi_h - 1, 1)
    cx = float(np.mean(xs)) / max(roi_w - 1, 1)
    # 粗略分區：右下角 ROI 再分成 3x3 區域
    if cx > 0.66 and cy > 0.66:
      position_label = "bottom_right_corner"
    elif cx > 0.66:
      position_label = "right_side"
    elif cy > 0.66:
      position_label = "bottom_side"
    else:
      position_label = "inner_roi"

  return has_watermark, position_label


def main() -> int:
  if not os.path.isdir(ASSETS_ROOT):
    print(f"找不到 assets 目錄: {ASSETS_ROOT}", file=sys.stderr)
    return 1

  image_paths = iter_image_files(ASSETS_ROOT)
  if not image_paths:
    print(f"在 {ASSETS_ROOT} 下沒有找到任何圖片文件（jpg/png/jpeg）。")
    return 0

  suspected: List[str] = []
  position_stats: Dict[str, int] = {}

  print(f"開始檢查圖片水印，共 {len(image_paths)} 張圖...")

  for path in image_paths:
    rel = os.path.relpath(path, PROJECT_ROOT)
    has_watermark, position_label = detect_watermark_roi(path)

    if has_watermark:
      print(f"[檢查中] {rel} ... 發現水印")
      suspected.append(rel)
    else:
      print(f"[檢查中] {rel} ... 無明顯水印")

    if position_label not in position_stats:
      position_stats[position_label] = 0
    position_stats[position_label] += 1

  # 生成報告（只寫入文本，不修改任何圖片）
  total_suspected = len(suspected)

  lines: List[str] = []
  lines.append("=== Watermark Detection Report ===")
  lines.append("")
  lines.append(f"疑似帶有水印的圖片總數: {total_suspected}")
  lines.append("")
  lines.append("疑似帶水印的文件列表:")
  if suspected:
    for p in suspected:
      lines.append(f"- {p}")
  else:
    lines.append("(無)")

  lines.append("")
  lines.append("水印位置分布統計（基於右下角 ROI）:")
  for pos, count in sorted(position_stats.items(), key=lambda x: x[0]):
    lines.append(f"- {pos}: {count}")

  os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
  with open(REPORT_PATH, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

  print("")
  print(f"檢查完成，報告已生成: {REPORT_PATH}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
