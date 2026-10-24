"""Draws the app icon: the Bengal, asleep, on the app's dark ink.

Not a placeholder. The cat is the app's own — the same Bengal palette
`CatColors.bengal` gives `SleepingCat`, and the same closed-eye arcs — so the
home screen and the welcome screen are recognisably one thing.

Why a cat and not the paw mark: a paw is what four other pet apps use. The
face is this app's. And why on ink rather than the brand amber: the Bengal's
coat *is* amber, so cat-on-amber had almost no contrast. Dark also echoes the
disc the pill button holds its mark in.

Every size is drawn at its own resolution rather than resized down from one
master: a 20-pixel icon supersampled from the shape beats the same icon
squeezed out of a 1024-pixel one, and nothing here can pick up an alpha
channel, which iOS rejects.

Regenerate the lot with:

    tool/make_icons.sh

or one size:

    python3 -I tool/make_icon.py <path> [size]
"""

import math
import struct
import sys
import zlib

SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 1024

# The app's ink and the Bengal's coat, from app_theme.dart and
# cat_illustration.dart. Change one, change both.
INK_TOP = (0x3A, 0x2D, 0x23)
INK_BOTTOM = (0x1E, 0x17, 0x12)
COAT = (0xD9, 0xA8, 0x6C)
PALE = (0xF5, 0xE6, 0xCC)
MARKING = (0x4A, 0x35, 0x24)
NOSE = (0xD1, 0x87, 0x7F)
EAR = (0xE9, 0xBC, 0xA8)


# How much of the tile the cat takes. Measured off the drawing: ear tips at
# 0.152, chin at 0.846, so the shape is already centred and only needs
# opening out. Much past this and the ears meet the rounded corner iOS masks
# the icon with.
GROW = 1.10


def fx(x):
    return 0.5 + (x - 0.5) * GROW


def fy(y):
    return 0.5 + (y - 0.5) * GROW


def ellipse(cx, cy, rx, ry):
    """A filled ellipse, and the box it lives in."""
    cx, cy, rx, ry = fx(cx), fy(cy), rx * GROW, ry * GROW

    def hit(x, y):
        return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0

    return hit, (cx - rx, cy - ry, cx + rx, cy + ry)


def triangle(a, b, c):
    """A filled triangle, by the sign of each edge."""
    a, b, c = [(fx(p[0]), fy(p[1])) for p in (a, b, c)]

    def side(p, q, x, y):
        return (q[0] - p[0]) * (y - p[1]) - (q[1] - p[1]) * (x - p[0])

    def hit(x, y):
        d1, d2, d3 = side(a, b, x, y), side(b, c, x, y), side(c, a, x, y)
        has_neg = d1 < 0 or d2 < 0 or d3 < 0
        has_pos = d1 > 0 or d2 > 0 or d3 > 0
        return not (has_neg and has_pos)

    xs, ys = (a[0], b[0], c[0]), (a[1], b[1], c[1])
    return hit, (min(xs), min(ys), max(xs), max(ys))


def stroke(a, b, width):
    """A line with round caps: every point within [width] / 2 of it."""
    a, b = (fx(a[0]), fy(a[1])), (fx(b[0]), fy(b[1]))
    half = width * GROW / 2
    dx, dy = b[0] - a[0], b[1] - a[1]
    length_sq = dx * dx + dy * dy or 1e-9

    def hit(x, y):
        t = ((x - a[0]) * dx + (y - a[1]) * dy) / length_sq
        t = 0.0 if t < 0 else (1.0 if t > 1 else t)
        px, py = a[0] + dx * t, a[1] + dy * t
        return (x - px) ** 2 + (y - py) ** 2 <= half * half

    xs, ys = (a[0], b[0]), (a[1], b[1])
    return hit, (min(xs) - half, min(ys) - half, max(xs) + half, max(ys) + half)


def arc(cx, cy, rx, ry, width, start, end):
    """A stroked elliptical arc, for an eye closed in contentment.

    Angles are measured with y pointing down, so the upper half of the
    ellipse — the arc that curves over like a sleeping eye — runs from -pi
    to 0.
    """
    cx, cy, rx, ry = fx(cx), fy(cy), rx * GROW, ry * GROW
    half = width * GROW / 2

    def hit(x, y):
        dx, dy = (x - cx) / rx, (y - cy) / ry
        radius = math.hypot(dx, dy)
        if radius < 1e-6:
            return False
        # Back to canvas units, so the stroke keeps its thickness where the
        # ellipse is tightest.
        if abs(radius - 1.0) * min(rx, ry) > half:
            return False
        angle = math.atan2(dy, dx)
        return start <= angle <= end

    return hit, (cx - rx - half, cy - ry - half, cx + rx + half, cy + ry + half)


def shrink(points, factor):
    """Pulls a polygon towards its own middle, for an inner ear."""
    mx = sum(p[0] for p in points) / len(points)
    my = sum(p[1] for p in points) / len(points)
    return [
        (mx + (p[0] - mx) * factor, my + (p[1] - my) * factor) for p in points
    ]


# The outer corner stays *inside* the head's silhouette. Pushed past it the
# ears stop being ears and become wings.
LEFT_EAR = [(0.238, 0.152), (0.268, 0.404), (0.470, 0.327)]
RIGHT_EAR = [(0.762, 0.152), (0.732, 0.404), (0.530, 0.327)]

# Detail that earns its place at size but not below it. A mouth two pixels
# across is not a mouth, it is a smudge on an otherwise clean muzzle —
# which is the whole reason icons come in separate sizes rather than one
# image resized.
DETAILED = SIZE >= 120

# Front to back: the first shape a sample lands in wins.
LAYERS = [
    # The eyes, closed. The one thing that has to survive at 40 pixels.
    #
    # The arc stops short of the ellipse's widest point at either end: run
    # the full half and the ends turn vertical, which reads as a croquet
    # hoop rather than a lid.
    (arc(0.376, 0.592, 0.086, 0.050, 0.021, -2.76, -0.38), MARKING),
    (arc(0.624, 0.592, 0.086, 0.050, 0.021, -2.76, -0.38), MARKING),
    # The mouth: two small cups meeting under the nose.
    *(
        [
            (arc(0.468, 0.702, 0.032, 0.028, 0.013, 0.30, math.pi - 0.30),
             MARKING),
            (arc(0.532, 0.702, 0.032, 0.028, 0.013, 0.30, math.pi - 0.30),
             MARKING),
        ]
        if DETAILED
        else []
    ),
    (triangle((0.474, 0.654), (0.526, 0.654), (0.500, 0.696)), NOSE),
    # The muzzle: two cheeks and the chin under them, merged.
    (ellipse(0.446, 0.702, 0.096, 0.073), PALE),
    (ellipse(0.554, 0.702, 0.096, 0.073), PALE),
    (ellipse(0.500, 0.718, 0.126, 0.060), PALE),
    # Three forehead stripes. Bengal enough to place the cat, faint enough
    # to blur into warmth rather than dirt when the icon is small.
    (stroke((0.437, 0.352), (0.421, 0.436), 0.026), MARKING),
    (stroke((0.500, 0.330), (0.500, 0.420), 0.026), MARKING),
    (stroke((0.563, 0.352), (0.579, 0.436), 0.026), MARKING),
    (triangle(*shrink(LEFT_EAR, 0.54)), EAR),
    (triangle(*shrink(RIGHT_EAR, 0.54)), EAR),
    (triangle(*LEFT_EAR), COAT),
    (triangle(*RIGHT_EAR), COAT),
    (ellipse(0.500, 0.568, 0.305, 0.278), COAT),
]


def colour_at(x, y):
    for (hit, (x0, y0, x1, y1)), rgb in LAYERS:
        if x0 <= x <= x1 and y0 <= y <= y1 and hit(x, y):
            return rgb
    # A gentle warm fall from top to bottom. Flat ink would do; this is one
    # shade better and costs a subtraction.
    return (
        round(INK_TOP[0] + (INK_BOTTOM[0] - INK_TOP[0]) * y),
        round(INK_TOP[1] + (INK_BOTTOM[1] - INK_TOP[1]) * y),
        round(INK_TOP[2] + (INK_BOTTOM[2] - INK_TOP[2]) * y),
    )


# Supersampling, so the curves are not jagged. Heavier at small sizes, where
# a single pixel carries much more of a curve and the whole grid is cheap.
SS = 2 if SIZE >= 256 else 4
OFFSETS = [(i + 0.5) / SS for i in range(SS)]
SAMPLES = SS * SS

rows = []
for py in range(SIZE):
    row = bytearray([0])
    for px in range(SIZE):
        r = g = b = 0
        for ox in OFFSETS:
            for oy in OFFSETS:
                sample = colour_at((px + ox) / SIZE, (py + oy) / SIZE)
                r += sample[0]
                g += sample[1]
                b += sample[2]
        row += bytes((r // SAMPLES, g // SAMPLES, b // SAMPLES))
    rows.append(bytes(row))

raw = b"".join(rows)


def chunk(tag, data):
    body = tag + data
    return (
        struct.pack(">I", len(data))
        + body
        + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    )


png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(raw, 9))
    + chunk(b"IEND", b"")
)
with open(sys.argv[1], "wb") as handle:
    handle.write(png)
print(f"wrote {sys.argv[1]} ({SIZE}px, {len(png)} bytes)")
