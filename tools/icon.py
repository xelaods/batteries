"""アプリアイコン（1024x1024）を作る：濃いグレーの地に、緑で満ちていく電池を3本"""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4  # 縁をなめらかにするため大きく描いて縮める
W = S * SS

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

top, bottom = (44, 46, 52), (16, 17, 20)
img = Image.new("RGB", (W, W))
d = ImageDraw.Draw(img)
for y in range(W):
    d.line([(0, y), (W, y)], fill=lerp(top, bottom, y / W))

GREEN = (52, 199, 89)
OUTLINE = (235, 236, 240)
levels = [0.35, 0.65, 1.0]
bw, bh = 200 * SS, 520 * SS
gap = 70 * SS
total = bw * 3 + gap * 2
x = (W - total) // 2
y0 = (W - bh) // 2 + 40 * SS
stroke = 26 * SS
r = 54 * SS
for lv in levels:
    # 端子
    tw, th = 80 * SS, 40 * SS
    d.rounded_rectangle((x + (bw - tw) // 2, y0 - th - 10 * SS, x + (bw + tw) // 2, y0 + 10 * SS), 14 * SS, fill=OUTLINE)
    d.rounded_rectangle((x, y0, x + bw, y0 + bh), r, outline=OUTLINE, width=stroke)
    inset = stroke + 18 * SS
    inner_h = bh - inset * 2
    fh = int(inner_h * lv)
    d.rounded_rectangle((x + inset, y0 + bh - inset - fh, x + bw - inset, y0 + bh - inset), r - inset // 2, fill=GREEN)
    x += bw + gap

img = img.resize((S, S), Image.LANCZOS)
img.save(sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png")
