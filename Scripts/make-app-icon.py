#!/usr/bin/env python3
"""Draws Zeitkonto's app icon.

A script rather than a checked-in binary nobody can edit: the mark is a navy
hard hat on a warm amber field — the job site, where the hours are worked.
Change the numbers below and run it; the PNG is the output, not the source.

Every shape is a signed distance (negative inside, positive outside), which
gives clean anti-aliased edges and the soft shadow under the hat without an
imaging library.

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

FIELD_TOP_LEFT = (0xFF, 0xBA, 0x40)
FIELD_BOTTOM_RIGHT = (0xF0, 0x80, 0x1E)
GLOW = (0xFF, 0xF0, 0xC8)
GLOW_STRENGTH = 0.35      # how much the soft light at the top left lifts the field
GLOW_CENTRE = (230, 70)
GLOW_RADII = (530, 490)
GLOW_SOFTNESS = 140
HAT = (0x18, 0x22, 0x54)
RIDGE = (0x2C, 0x3A, 0x80)

CENTRE_X = 512
DOME_RADIUS = 250
DOME_BASE = 600           # the dome is the top half of a circle centred here
BRIM = (182, 610, 842, 696)   # left, top, right, bottom
BRIM_RADIUS = 43
RIDGE_BOX = (478, 382, 546, 590)
RIDGE_RADIUS = 34
SHADOW_OFFSET = 16
SHADOW_SOFTNESS = 30
SHADOW_STRENGTH = 0.27


def rounded_box(x, y, box, radius):
    """Signed distance to a rounded rectangle."""
    left, top, right, bottom = box
    cx, cy = (left + right) / 2, (top + bottom) / 2
    qx = abs(x - cx) - (right - left) / 2 + radius
    qy = abs(y - cy) - (bottom - top) / 2 + radius
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    return outside + min(max(qx, qy), 0.0) - radius


def hat(x, y):
    """Signed distance to the dome and the brim together."""
    dome = max(math.hypot(x - CENTRE_X, y - DOME_BASE) - DOME_RADIUS, y - DOME_BASE)
    return min(dome, rounded_box(x, y, BRIM, BRIM_RADIUS))


def coverage(distance):
    """How much of a pixel a shape covers, from its distance at the pixel centre."""
    return min(1.0, max(0.0, 0.5 - distance))


def blurred(distance, softness):
    """A shape's edge seen through a Gaussian blur."""
    return 0.5 * math.erfc(distance / (softness * math.sqrt(2)))


def mix(under, over, amount):
    return tuple(a + (b - a) * amount for a, b in zip(under, over))


def colour_at(x, y):
    t = (x + y) / (2 * SIZE)
    colour = mix(FIELD_TOP_LEFT, FIELD_BOTTOM_RIGHT, t)
    gx, gy = (x - GLOW_CENTRE[0]) / GLOW_RADII[0], (y - GLOW_CENTRE[1]) / GLOW_RADII[1]
    glow_distance = (math.hypot(gx, gy) - 1) * min(GLOW_RADII)
    colour = mix(colour, GLOW, GLOW_STRENGTH * blurred(glow_distance, GLOW_SOFTNESS))
    shadow = SHADOW_STRENGTH * blurred(hat(x, y - SHADOW_OFFSET), SHADOW_SOFTNESS)
    colour = mix(colour, (0, 0, 0), shadow)
    colour = mix(colour, HAT, coverage(hat(x, y)))
    return mix(colour, RIDGE, coverage(rounded_box(x, y, RIDGE_BOX, RIDGE_RADIUS)))


def render():
    rows = bytearray()
    for py in range(SIZE):
        rows.append(0)  # PNG filter type: none
        for px in range(SIZE):
            rows.extend(round(c) for c in colour_at(px + 0.5, py + 0.5))
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
