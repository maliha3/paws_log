"""Draws the placeholder app icon: a cream paw on the app's green.

A placeholder, not a design — it exists so the app does not ship with the
Flutter logo. Regenerate with:

    python3 -I tool/make_icon.py assets/app_icon.png

then resize into ios/Runner/Assets.xcassets/AppIcon.appiconset and the
android mipmap-* folders with `sips -z <px> <px>`.
"""
import math, struct, zlib, sys

SIZE = 1024
BG = (0x24, 0x4C, 0x3F)      # deep green, a darker step of the app's seed
FG = (0xE8, 0xF2, 0xEC)      # near-white with a green cast

def ellipse(px, py, cx, cy, rx, ry, rot=0.0):
    """Signed coverage test for a rotated ellipse."""
    dx, dy = px - cx, py - cy
    if rot:
        c, s = math.cos(-rot), math.sin(-rot)
        dx, dy = dx * c - dy * s, dx * s + dy * c
    return (dx / rx) ** 2 + (dy / ry) ** 2 <= 1.0

# One pad and four toes, in units of the canvas.
PAD = (0.50, 0.70, 0.235, 0.185, 0.0)
TOES = [
    (0.215, 0.395, 0.082, 0.108, -0.46),
    (0.405, 0.275, 0.084, 0.118, -0.16),
    (0.595, 0.275, 0.084, 0.118, 0.16),
    (0.785, 0.395, 0.082, 0.108, 0.46),
]

def paw(px, py):
    x, y = px / SIZE, py / SIZE
    if ellipse(x, y, PAD[0], PAD[1], PAD[2], PAD[3], PAD[4]):
        return True
    return any(ellipse(x, y, *toe) for toe in TOES)

rows = []
# 2x2 supersampling, so the curves are not jagged.
for py in range(SIZE):
    row = bytearray([0])
    for px in range(SIZE):
        hits = sum(
            paw(px + ox, py + oy) for ox in (0.25, 0.75) for oy in (0.25, 0.75)
        )
        a = hits / 4
        row += bytes(
            round(BG[i] + (FG[i] - BG[i]) * a) for i in range(3)
        )
    rows.append(bytes(row))

raw = b"".join(rows)

def chunk(tag, data):
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(
        ">I", zlib.crc32(body) & 0xFFFFFFFF
    )

png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(raw, 9))
    + chunk(b"IEND", b"")
)
with open(sys.argv[1], "wb") as handle:
    handle.write(png)
print(f"wrote {sys.argv[1]} ({len(png)} bytes)")
