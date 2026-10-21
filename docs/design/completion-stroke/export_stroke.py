# 完了の線（App/Components/Flourishes.swift の CompletionStroke）を、コードと同じ比率で画像にする
# 使い方：python3 export_stroke.py <書き出し先フォルダ>（Pillow と日本語フォントが必要。FONT のパスは環境に合わせて変える）
from PIL import Image, ImageDraw, ImageFont
import os, sys
OUT = sys.argv[1]
FONT = "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"  # iPhone のシステムフォントの代わり
LIGHT = (0x2B, 0x4C, 0x9B); DARK = (0x5E, 0x7F, 0xD6)
# iPhone 幅393pt: 画面の余白16pt×2、カード内の余白14pt×2 → 筆跡画像の幅 333pt
CARD_W_PT = 393 - 16 * 2 - 14 * 2
SAMPLE_W, SAMPLE_H = 900, 440           # SampleData のカード画像
CARD_H_PT = CARD_W_PT * SAMPLE_H / SAMPLE_W
LINE_PT, INSET_PT, RADIUS_PT = 4, 12, 10
SS = 3                                  # なめらかにするため3倍で描いて縮小

def ink_line(draw, x0, x1, y, width, color):
    """丸い端（lineCap: .round）の線。端は太さの半分だけ外にはみ出る"""
    r = width / 2
    if x1 > x0:
        draw.rectangle((x0, y - r, x1, y + r), fill=color)
    draw.ellipse((x0 - r, y - r, x0 + r, y + r), fill=color)
    draw.ellipse((x1 - r, y - r, x1 + r, y + r), fill=color)

def card(scale, accent, progress=1.0):
    """筆跡カード（サンプル）＋完了の線。scale は 1pt あたりのピクセル数"""
    s = scale * SS
    w, h = round(CARD_W_PT * s), round(CARD_H_PT * s)
    k = w / SAMPLE_W                      # サンプル画像の1px → 出力px
    img = Image.new("RGB", (w, h), (235, 235, 235))   # UIColor(white: 0.92)
    d = ImageDraw.Draw(img)
    y = 40 * k
    for i, (text, size, color) in enumerate([("鑑定理論", 120, (31, 59, 138)), ("総則 1〜3", 92, (38, 38, 38))]):
        font = ImageFont.truetype(FONT, round(size * k))
        box = d.textbbox((0, 0), text, font=font)
        d.text(((w - (box[2] - box[0])) / 2 - box[0], y), text, font=font, fill=color)
        y += size * k * 1.2 + 16 * k
    d.rectangle((120 * k, (SAMPLE_H - 80) * k, 164 * k, (SAMPLE_H - 36) * k), outline=(38, 38, 38), width=round(5 * k))
    # 完了の線：高さの真ん中、左右 12pt 内側、太さ 4pt、左→右に progress まで
    if progress > 0:
        x0, x1 = INSET_PT * s, w - INSET_PT * s
        ink_line(d, x0, x0 + (x1 - x0) * progress, h / 2, LINE_PT * s, accent)
    # 角丸 10pt
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=RADIUS_PT * s, fill=255)
    return img, mask

def on_background(scale, accent, bg, progress=1.0, pad_pt=16):
    img, mask = card(scale, accent, progress)
    pad = round(pad_pt * scale * SS)
    canvas = Image.new("RGB", (img.width + pad * 2, img.height + pad * 2), bg)
    canvas.paste(img, (pad, pad), mask)
    return canvas.resize((canvas.width // SS, canvas.height // SS), Image.LANCZOS)

# 1・2：カードの上の完了の線（@3x）。背景はカード欄の色（ライト #FFFFFF／ダーク #1C1C1E）
on_background(3, LIGHT, (255, 255, 255)).save(os.path.join(OUT, "01_card_light@3x.png"))
on_background(3, DARK, (28, 28, 30)).save(os.path.join(OUT, "02_card_dark@3x.png"))

# 3：左から右へ（easeOut 0.25秒）。0・0.05・0.10・0.25 秒の4コマ
def ease_out(t):
    # SwiftUI の .easeOut = cubic-bezier(0, 0, 0.58, 1)。t（時間）から進み具合を求める
    lo, hi = 0.0, 1.0
    for _ in range(60):
        u = (lo + hi) / 2
        x = 3 * (1 - u) ** 2 * u * 0 + 3 * (1 - u) * u ** 2 * 0.58 + u ** 3
        lo, hi = (u, hi) if x < t else (lo, u)
    u = (lo + hi) / 2
    return 3 * (1 - u) * u ** 2 * 1 + u ** 3 + 3 * (1 - u) ** 2 * u * 0
frames = [on_background(2, LIGHT, (255, 255, 255), ease_out(t / 0.25), pad_pt=8) for t in (0.0, 0.05, 0.10, 0.25)]
sheet = Image.new("RGB", (frames[0].width, frames[0].height * 4), (255, 255, 255))
for i, f in enumerate(frames):
    sheet.paste(f, (0, i * f.height))
sheet.save(os.path.join(OUT, "03_progress_light@2x.png"))

# 4・5：線だけ（透明背景、@3x）。長さ = 333 − 12×2 = 309pt、太さ 4pt、丸い端
def stroke_only(accent, scale=3, pad_pt=4):
    s = scale * SS
    length = (CARD_W_PT - INSET_PT * 2) * s
    pad = pad_pt * s + LINE_PT * s / 2
    w, h = round(length + pad * 2), round(LINE_PT * s + pad_pt * s * 2)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ink_line(ImageDraw.Draw(img), pad, pad + length, h / 2, LINE_PT * s, accent + (255,))
    return img.resize((w // SS, h // SS), Image.LANCZOS)
stroke_only(LIGHT).save(os.path.join(OUT, "04_stroke_only_light@3x.png"))
stroke_only(DARK).save(os.path.join(OUT, "05_stroke_only_dark@3x.png"))

# 6：アイコン用の正方形の切り抜き（1024px）。カードの中央、線が筆跡を横切るところ
scale = 1024 / CARD_H_PT
img, mask = card(scale, LIGHT)
crop = img.crop(((img.width - 1024 * SS) // 2, 0, (img.width + 1024 * SS) // 2, 1024 * SS))
crop.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "06_icon_crop_light_1024.png"))

# 7：SVG（拡大しても劣化しない）。値はコードと同じ pt 単位
for name, color in (("light", "#2B4C9B"), ("dark", "#5E7FD6")):
    L = CARD_W_PT - INSET_PT * 2
    open(os.path.join(OUT, f"07_stroke_{name}.svg"), "w").write(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{L + 8}" height="8" viewBox="0 0 {L + 8} 8">\n'
        f'  <!-- 完了の線：長さ {L}pt、太さ {LINE_PT}pt、丸い端、色 {color} -->\n'
        f'  <line x1="4" y1="4" x2="{L + 4}" y2="4" stroke="{color}" stroke-width="{LINE_PT}" stroke-linecap="round"/>\n'
        f'</svg>\n')
print("card pt:", CARD_W_PT, "x", round(CARD_H_PT, 1))

# 6b：線の右端（丸い端と、カードの縁との 12pt のすき間）。背景はカード欄の白
os.rename(os.path.join(OUT, "06_icon_crop_light_1024.png"), os.path.join(OUT, "06a_icon_crop_center_1024.png"))
img, mask = card(scale, LIGHT)
canvas = Image.new("RGB", (img.width + 200 * SS, img.height), (255, 255, 255))
canvas.paste(img, (0, 0), mask)
right = canvas.crop((canvas.width - 1024 * SS, 0, canvas.width, 1024 * SS))
right.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "06b_icon_crop_end_1024.png"))
