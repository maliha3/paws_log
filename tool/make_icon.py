"""Draws the app icon: the app's ink paw on its amber.

A placeholder, not a design — it exists so the app does not ship with the
Flutter logo. The colours are the brand's own, taken from
lib/core/theme/app_theme.dart, and the geometry is the same pad and four
toes that `PawMark` draws in the app: change one, change both.

Every size is drawn at its own resolution rather than resized down from one
master: a 20-pixel icon supersampled from the shape beats the same icon
squeezed out of a 1024-pixel one, and nothing here can pick up an alpha
channel, which iOS rejects.

Regenerate the lot with:

    tool/make_icons.sh

or one size:

    python3 -I tool/make_icon.py assets/app_icon.png [size]
"""
import math, struct, zlib, sys

SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
BG = (0xEE, 0x9A, 0x3A)      # the brand amber, _brand in app_theme.dart
FG = (0x2A, 0x21, 0x1B)      # the near-black ink the solid controls use

# How much of the canvas the mark fills. The rest is breathing room: iOS
# rounds the corners and a home screen is crowded, so a paw that reached the
# edge would read as a smudge at 40 pixels.
INSET = 0.78

# The drawn shape sits low in its box — the pad is at 0.70 — so centring it
# means centring on where the ink actually is, not on the pad.
INK_CENTRE_Y = 0.521

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

def fit(shape):
    """Shrinks a shape towards the middle of the canvas.

    Framing only: the proportions are untouched, so this stays the same paw
    `PawMark` draws, just with a margin around it.
    """
    cx, cy, rx, ry, rot = shape
    return (
        0.5 + (cx - 0.5) * INSET,
        0.5 + (cy - INK_CENTRE_Y) * INSET,
        rx * INSET,
        ry * INSET,
        rot,
    )


PAD = fit(PAD)
TOES = [fit(toe) for toe in TOES]


def paw(px, py):
    x, y = px / SIZE, py / SIZE
    if ellipse(x, y, PAD[0], PAD[1], PAD[2], PAD[3], PAD[4]):
        return True
    return any(ellipse(x, y, *toe) for toe in TOES)

# Supersampling, so the curves are not jagged. Heavier at small sizes, where
# a single pixel carries much more of a curve and the whole grid is cheap.
SS = 2 if SIZE >= 256 else 4
OFFSETS = [(i + 0.5) / SS for i in range(SS)]

rows = []
for py in range(SIZE):
    row = bytearray([0])
    for px in range(SIZE):
        hits = sum(
            paw(px + ox, py + oy) for ox in OFFSETS for oy in OFFSETS
        )
        a = hits / (SS * SS)
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
