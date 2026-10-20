"""Render the LinguaPatente "road P" launcher icon (direction 3).

Outputs, all 1024x1024:
  assets/images/app_icon.png               full icon, yellow background (iOS + legacy Android)
  assets/icon_src/app_icon_foreground.png  transparent foreground for Android adaptive icons

Geometry matches app_icon.svg (viewBox 0 0 1024 1024). The artwork stays inside
the central ~50% so Android circle/squircle masks never clip it.

Usage: python3 assets/icon_src/render_app_icon.py   (needs Pillow)
"""
import math
import os

from PIL import Image, ImageDraw

SS = 4  # supersampling factor
N = 1024 * SS
YELLOW = (255, 194, 14, 255)
INK = (19, 32, 26, 255)
WHITE = (255, 255, 255, 255)
GREEN = (10, 107, 69, 255)

ROAD_W = 150
DASH_W = 16
DASH, GAP = 44, 36
STEM_X, TOP_Y, BOTTOM_Y, BOWL_Y = 380, 330, 780, 610
BOWL_CX, BOWL_CY, BOWL_R = 560, 470, 140


def s(v):
    return v * SS


def path_points(step=1.0):
    """Centerline from the start dot up the stem, round the bowl, back to the stem."""
    pts = []
    y = BOTTOM_Y
    while y > TOP_Y:
        pts.append((STEM_X, y))
        y -= step
    x = STEM_X
    while x < BOWL_CX:
        pts.append((x, TOP_Y))
        x += step
    arc_len = math.pi * BOWL_R
    n = int(arc_len / step)
    for i in range(n):
        t = -math.pi / 2 + math.pi * i / n
        pts.append((BOWL_CX + BOWL_R * math.cos(t), BOWL_CY + BOWL_R * math.sin(t)))
    x = BOWL_CX
    while x > STEM_X:
        pts.append((x, BOWL_Y))
        x -= step
    pts.append((STEM_X, BOWL_Y))
    return pts


def draw_icon(img):
    d = ImageDraw.Draw(img)
    half = ROAD_W / 2
    # Road body: stem, top bar, bowl ring, bottom bar; round join at the top-left corner.
    d.rectangle([s(STEM_X - half), s(TOP_Y), s(STEM_X + half), s(BOTTOM_Y)], fill=INK)
    d.rectangle([s(STEM_X), s(TOP_Y - half), s(BOWL_CX), s(TOP_Y + half)], fill=INK)
    d.rectangle([s(STEM_X), s(BOWL_Y - half), s(BOWL_CX), s(BOWL_Y + half)], fill=INK)
    d.ellipse([s(STEM_X - half), s(TOP_Y - half), s(STEM_X + half), s(TOP_Y + half)], fill=INK)
    outer = BOWL_R + half
    inner = BOWL_R - half
    ring = Image.new('L', (N, N), 0)
    rd = ImageDraw.Draw(ring)
    rd.ellipse([s(BOWL_CX - outer), s(BOWL_CY - outer), s(BOWL_CX + outer), s(BOWL_CY + outer)], fill=255)
    rd.ellipse([s(BOWL_CX - inner), s(BOWL_CY - inner), s(BOWL_CX + inner), s(BOWL_CY + inner)], fill=0)
    rd.rectangle([0, 0, s(BOWL_CX), N], fill=0)  # keep only the right half of the ring
    img.paste(INK, (0, 0), ring)

    # Dashed white centerline, each dash filled as a polygon so curves stay smooth.
    # Skip where the bottom bar re-enters the stem.
    pts = path_points()
    dashes, current, dist = [], [], 0.0
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        on = (dist % (DASH + GAP)) < DASH
        on = on and not (
            y0 == y1 == BOWL_Y and min(x0, x1) < STEM_X + half + 6)
        if on:
            current.append((x0, y0))
        elif current:
            current.append((x0, y0))
            dashes.append(current)
            current = []
        dist += math.hypot(x1 - x0, y1 - y0)
    if current:
        dashes.append(current)
    hw = DASH_W / 2
    for dash in dashes:
        length = sum(math.hypot(b[0] - a[0], b[1] - a[1])
                     for a, b in zip(dash, dash[1:]))
        if length < 4:  # drop slivers left where the bars meet the stem
            continue
        left, right = [], []
        for i, (x, y) in enumerate(dash):
            ax, ay = dash[max(i - 1, 0)]
            bx, by = dash[min(i + 1, len(dash) - 1)]
            tx, ty = bx - ax, by - ay
            ln = math.hypot(tx, ty) or 1.0
            nx, ny = -ty / ln, tx / ln
            left.append((s(x + nx * hw), s(y + ny * hw)))
            right.append((s(x - nx * hw), s(y - ny * hw)))
        d.polygon(left + right[::-1], fill=WHITE)

    # Green start dot with white ring.
    for r, color in ((66, WHITE), (50, GREEN)):
        d.ellipse([s(STEM_X - r), s(BOTTOM_Y - r), s(STEM_X + r), s(BOTTOM_Y + r)], fill=color)


# The drawn artwork's bounding box centre; render() scales it about this point
# and recentres it, keeping every part inside the adaptive-icon safe circle.
ART_CENTER = (540, 550)
# Full icon (iOS, legacy Android) fills more of the tile; the adaptive
# foreground must keep everything inside Android's 66dp safe circle
# (radius 313 of 1024), so it is drawn smaller.
FULL_SCALE = 0.92
FOREGROUND_SCALE = 0.80


def render(background, scale):
    img = Image.new('RGBA', (N, N), background)
    draw_icon(img)
    inv = 1 / scale
    img = img.transform(
        (N, N),
        Image.AFFINE,
        (inv, 0, s(ART_CENTER[0]) - s(512) * inv,
         0, inv, s(ART_CENTER[1]) - s(512) * inv),
        resample=Image.BICUBIC,
        fillcolor=background,
    )
    return img.resize((1024, 1024), Image.LANCZOS)


def main():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    full = render(YELLOW, FULL_SCALE).convert('RGB')
    full.save(os.path.join(root, 'assets/images/app_icon.png'), optimize=True)
    fg = render((0, 0, 0, 0), FOREGROUND_SCALE)
    fg.save(os.path.join(root, 'assets/icon_src/app_icon_foreground.png'), optimize=True)
    print('rendered app_icon.png and app_icon_foreground.png')


if __name__ == '__main__':
    main()
