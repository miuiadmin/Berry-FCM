#!/usr/bin/env python3
"""Generate banner.png for Berry-FCM (896x448) — stdlib only."""
import struct, zlib, math, os

W, H = 896, 448

def lerp(a, b, t): return int(a + (b - a) * t)

def bg(x, y):
    t = y / H
    r = lerp(0x1a, 0x0d, t); g = lerp(0x12, 0x0a, t); b = lerp(0x26, 0x10, t)
    # 右侧微亮对角光
    glow = max(0.0, 1 - math.hypot(x - W * 0.72, y - H * 0.28) / (W * 0.7))
    r = min(255, int(r + 40 * glow)); g = min(255, int(g + 18 * glow)); b = min(255, int(b + 60 * glow))
    return (r, g, b)

def berry(cx, cy, rad):
    """Return (r,g,b) or None — berry body with radial shade + highlight + leaf."""
    def px(x, y):
        dx, dy = x - cx, y - cy
        d = math.hypot(dx, dy)
        if d <= rad:
            t = min(1.0, math.hypot(dx - rad * 0.35, dy - rad * 0.35) / (rad * 1.15))
            return (lerp(0xF2, 0x5B, t), lerp(0x57, 0x21, t), lerp(0x9B, 0xB6, t))
        return None
    return px

FONT = {
 'B': ["11110","10001","10001","11110","10001","10001","11110"],
 'e': ["00000","01110","10001","11111","10000","01110","00000"],
 'r': ["00000","00000","10110","11001","10000","10000","10000"],
 'y': ["00000","10001","10001","01010","00100","01000","11000"],
 '-': ["00000","00000","00000","11111","00000","00000","00000"],
 'F': ["11111","10000","10000","11110","10000","10000","10000"],
 'C': ["01110","10001","10000","10000","10000","10001","01110"],
 'M': ["10001","11011","10101","10101","10001","10001","10001"],
 'U': ["10001","10001","10001","10001","10001","10001","01110"],
 'A': ["01110","10001","10001","11111","10001","10001","10001"],
 'R': ["11110","10001","10001","11110","10100","10010","10001"],
 'D': ["11110","10001","10001","10001","10001","10001","11110"],
 'I': ["11111","00100","00100","00100","00100","00100","11111"],
 'N': ["10001","11001","10101","10011","10001","10001","10001"],
 'G': ["01110","10001","10000","10011","10001","10001","01111"],
 ' ': ["0000","0000","0000","0000","0000","0000","0000"],
}

def draw_text(px_map, text, x0, y0, scale, color):
    for i, ch in enumerate(text):
        rows = FONT.get(ch)
        if not rows: continue
        for ry, row in enumerate(rows):
            for rx, c in enumerate(row):
                if c == '1':
                    for sy in range(scale):
                        for sx in range(scale):
                            X = x0 + (i * (5 + 2) + rx) * scale + sx
                            Y = y0 + ry * scale + sy
                            if 0 <= X < W and 0 <= Y < H:
                                px_map[(X, Y)] = color

img = {}
# — berry body —
bfn = berry(250, 258, 130)
# leaf: green diamond above berry
for yy in range(H):
    for xx in range(0, W):
        c = bfn(xx, yy)
        if c: img[(xx, yy)] = c
# leaf + stem
for yy in range(96, 150):
    for xx in range(244, 262):
        d = abs(xx - 253) / 9 + abs(yy - 123) / 27
        if d <= 1: img[(xx, yy)] = (0x34, 0xd3, 0x99)
# specular highlight
for yy in range(160, 210):
    for xx in range(160, 230):
        if math.hypot(xx - 195, yy - 185) / 46 <= 1:
            a = 1 - math.hypot(xx - 195, yy - 185) / 46
            base = img.get((xx, yy), (0, 0, 0))
            img[(xx, yy)] = tuple(min(255, int(v + (255 - v) * a * 0.5)) for v in base)

draw_text(img, "Berry-FCM", 428, 168, 7, (0xEF, 0xE9, 0xF5))
draw_text(img, "FCM GUARDIAN", 432, 296, 4, (0xB4, 0x93, 0xD2))

rows = []
for y in range(H):
    row = bytearray([0])
    for x in range(W):
        row += bytes(img.get((x, y), bg(x, y)))
    rows.append(bytes(row))
raw = b''.join(rows)

def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(raw, 9))
       + chunk(b'IEND', b''))

out = os.path.join(os.path.dirname(__file__), '..', 'banner.png')
with open(out, 'wb') as f:
    f.write(png)
print("wrote", os.path.normpath(out), len(png), "bytes")
