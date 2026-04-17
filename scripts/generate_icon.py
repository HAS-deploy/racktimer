#!/usr/bin/env python3
"""
RackTimer 1024x1024 app icon.
Flat gradient timer dial with a centered barbell silhouette. No transparency,
no text, no Apple device imagery, square (iOS rounds the corners). Passes
App Store Connect 1024x1024 rules and is legible at 60x60.
"""
from PIL import Image, ImageDraw
from pathlib import Path

SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / "RackTimer" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
OUT.mkdir(parents=True, exist_ok=True)

def radial_bg():
    """Charcoal → electric-orange radial. High contrast, gym-vibe, unique at tiny sizes."""
    img = Image.new("RGB", (SIZE, SIZE), (15, 17, 22))  # near-black base
    px = img.load()
    cx, cy = SIZE / 2, SIZE / 2
    max_r = ((SIZE / 2) ** 2 + (SIZE / 2) ** 2) ** 0.5
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x - cx, y - cy
            r = (dx * dx + dy * dy) ** 0.5 / max_r
            t = min(1.0, max(0.0, 1.0 - r))
            # blend orange core -> dark rim
            r8 = int(15 + (255 - 15) * (t ** 1.8))
            g8 = int(17 + (114 - 17) * (t ** 2.0))
            b8 = int(22 + (38 - 22) * (t ** 2.2))
            px[x, y] = (r8, g8, b8)
    return img


def draw_dial(img):
    d = ImageDraw.Draw(img)
    cx, cy = SIZE // 2, SIZE // 2
    # Outer ring (white, bold)
    ring_r = 430
    ring_w = 46
    d.ellipse(
        [cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r],
        outline=(255, 255, 255),
        width=ring_w,
    )
    # Inner darker dial face
    face_r = ring_r - ring_w // 2 - 2
    d.ellipse(
        [cx - face_r, cy - face_r, cx + face_r, cy + face_r],
        fill=(15, 17, 22),
    )
    # Tick marks every 30° (12 total)
    import math
    for i in range(12):
        ang = math.radians(i * 30 - 90)
        # long tick at 12/3/6/9
        long_tick = i % 3 == 0
        r1 = face_r - (80 if long_tick else 50)
        r2 = face_r - 20
        w = 14 if long_tick else 8
        x1 = cx + r1 * math.cos(ang); y1 = cy + r1 * math.sin(ang)
        x2 = cx + r2 * math.cos(ang); y2 = cy + r2 * math.sin(ang)
        d.line([(x1, y1), (x2, y2)], fill=(255, 255, 255), width=w)


def draw_barbell(img):
    """Horizontal barbell across the dial: center bar + two weight stacks per side."""
    d = ImageDraw.Draw(img)
    cx, cy = SIZE // 2, SIZE // 2
    # Bar
    bar_half_w = 330
    bar_thick = 28
    d.rounded_rectangle(
        [cx - bar_half_w, cy - bar_thick // 2, cx + bar_half_w, cy + bar_thick // 2],
        radius=14,
        fill=(245, 245, 248),
    )
    # Plates (outer big, inner smaller) — saturated orange for pop
    plate_color_a = (255, 124, 46)   # outer — brighter orange
    plate_color_b = (255, 170, 92)   # inner — lighter
    # Per side: two rounded rectangles
    outer_w = 58
    inner_w = 44
    outer_h = 280
    inner_h = 210
    gap = 14
    for side in (-1, 1):
        # Outer
        x1 = cx + side * (bar_half_w - 8) - (outer_w // 2 if side == -1 else -outer_w // 2)
        # Simpler: compute outer rect positions
        # Left plate: outer at bar_half_w edge going outward
        pass

    # Left outer
    lx_outer_center = cx - bar_half_w - outer_w // 2 + 8
    d.rounded_rectangle(
        [lx_outer_center - outer_w // 2, cy - outer_h // 2,
         lx_outer_center + outer_w // 2, cy + outer_h // 2],
        radius=16, fill=plate_color_a,
    )
    # Left inner
    lx_inner_center = lx_outer_center + outer_w // 2 + gap + inner_w // 2
    d.rounded_rectangle(
        [lx_inner_center - inner_w // 2, cy - inner_h // 2,
         lx_inner_center + inner_w // 2, cy + inner_h // 2],
        radius=14, fill=plate_color_b,
    )
    # Right outer
    rx_outer_center = cx + bar_half_w + outer_w // 2 - 8
    d.rounded_rectangle(
        [rx_outer_center - outer_w // 2, cy - outer_h // 2,
         rx_outer_center + outer_w // 2, cy + outer_h // 2],
        radius=16, fill=plate_color_a,
    )
    # Right inner
    rx_inner_center = rx_outer_center - outer_w // 2 - gap - inner_w // 2
    d.rounded_rectangle(
        [rx_inner_center - inner_w // 2, cy - inner_h // 2,
         rx_inner_center + inner_w // 2, cy + inner_h // 2],
        radius=14, fill=plate_color_b,
    )


def main():
    img = radial_bg()
    draw_dial(img)
    draw_barbell(img)
    # Save 1024x1024 master
    icon_1024 = OUT / "icon-1024.png"
    img.save(icon_1024, "PNG")
    # iOS single-size catalog only needs the 1024; Contents.json handles it.
    contents = """{
  "images" : [
    { "size" : "1024x1024", "idiom" : "universal", "filename" : "icon-1024.png", "platform" : "ios" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
"""
    (OUT / "Contents.json").write_text(contents)
    print(f"wrote {icon_1024}")
    print(f"wrote {OUT / 'Contents.json'}")


if __name__ == "__main__":
    main()
