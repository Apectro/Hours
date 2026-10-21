#!/usr/bin/env python3
"""Draws Zeitkonto's app icon.

A script rather than a checked-in binary nobody can edit: the mark is a clock
whose amber wedge, sweeping from twelve, is the time banked so far — a
Zeitkonto is literally a time account — with the hand at its leading edge.
Change the numbers below and run it; the PNG is the output, not the source.

iOS app icons must be fully opaque — an alpha channel is rejected at upload —
so this writes 8-bit RGB with no transparency and lets the system apply its own
rounded mask. Pure standard library: no Pillow on the machines this runs on.

    python3 Scripts/make-app-icon.py
"""

import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
SUBSAMPLES = 3  # per axis, so 9 samples a pixel: edges that are not stepped

TOP = (0x16, 0x20, 0x4E)
BOTTOM = (0x2C, 0x4A, 0x94)
FACE = (0x18, 0x24, 0x56)
RING_COLOUR = (0xF4, 0xF5, 0xF9)
BANKED = (0xF0, 0xA8, 0x3E)

CENTRE = SIZE / 2
RING_OUTER = 352          # outer radius of the white ring
RING_WIDTH = 62
WEDGE_GAP = 26            # face showing between the ring and the wedge
SWEEP_DEGREES = 125       # how far the wedge has filled, clockwise from twelve
HAND_LENGTH = 178
HAND_WIDTH = 50
HUB_RADIUS = 44

RING_INNER = RING_OUTER - RING_WIDTH
WEDGE_RADIUS = RING_INNER - WEDGE_GAP
HAND_ANGLE = math.radians(SWEEP_DEGREES)          # clockwise from twelve
HAND_TIP = (CENTRE + HAND_LENGTH * math.sin(HAND_ANGLE),
            CENTRE - HAND_LENGTH * math.cos(HAND_ANGLE))


def background(y):
    t = y / (SIZE - 1)
    return tuple(a + (b - a) * t for a, b in zip(TOP, BOTTOM))


def near_segment(x, y, ax, ay, bx, by, radius):
    """Within `radius` of the segment a–b: a line with round caps."""
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    px, py = ax + t * dx - x, ay + t * dy - y
    return px * px + py * py <= radius * radius


def colour_at(x, y):
    """The colour of one sample point, painted back to front."""
    dx, dy = x - CENTRE, y - CENTRE
    distance = math.hypot(dx, dy)
    if distance > RING_OUTER:
        return None                                   # background
    if near_segment(x, y, CENTRE, CENTRE, *HAND_TIP, HAND_WIDTH / 2) or distance <= HUB_RADIUS:
        return RING_COLOUR
    if distance > RING_INNER:
        return RING_COLOUR
    if distance <= WEDGE_RADIUS:
        # Angle clockwise from twelve, 0...360.
        angle = math.degrees(math.atan2(dx, -dy)) % 360
        if angle <= SWEEP_DEGREES:
            return BANKED
    return FACE


def render():
    rows = bytearray()
    step = 1 / SUBSAMPLES
    offsets = [(i + 0.5) * step for i in range(SUBSAMPLES)]
    samples = SUBSAMPLES * SUBSAMPLES
    for py in range(SIZE):
        rows.append(0)  # PNG filter type: none
        fill = background(py + 0.5)
        far = abs(py + 0.5 - CENTRE) > RING_OUTER + 1
        for px in range(SIZE):
            if far or abs(px + 0.5 - CENTRE) > RING_OUTER + 1:
                rows.extend(round(c) for c in fill)
                continue
            total = [0.0, 0.0, 0.0]
            for oy in offsets:
                for ox in offsets:
                    colour = colour_at(px + ox, py + oy) or fill
                    total[0] += colour[0]
                    total[1] += colour[1]
                    total[2] += colour[2]
            rows.extend(round(c / samples) for c in total)
    return bytes(rows)


def png(raw):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit RGB, no alpha
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    out = Path(__file__).resolve().parent.parent / "Hours/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    out.write_bytes(png(render()))
    print(f"wrote {out.relative_to(Path.cwd()) if out.is_relative_to(Path.cwd()) else out}")
