#!/usr/bin/env python3
"""Draws Zeitkonto's app icon.

A script rather than a checked-in binary nobody can edit: the mark is a white
clock on the app's blue, with the part of the day already worked shaded in —
a time account filling up, which is what Zeitkonto means. The minute hand is
navy, the hour hand the orange the app uses for overtime. Change the numbers
below and run it; the PNG is the output, not the source.

Every shape is a signed distance (negative inside, positive outside), which
gives clean anti-aliased edges and the soft shadow under the face without an
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

FIELD_TOP = (0x4C, 0x8F, 0xDB)
FIELD_BOTTOM = (0x1E, 0x4E, 0x8C)
FACE = (0xFF, 0xFF, 0xFF)
WORKED = (0xDC, 0xE8, 0xF7)   # the shaded part of the day
NAVY = (0x15, 0x30, 0x5C)
ORANGE = (0xFF, 0x9F, 0x2E)

CENTRE = (512, 512)
FACE_RADIUS = 330
WORKED_RADIUS = 290
WORKED_TO = 150               # degrees clockwise from twelve: five o'clock
MINUTE = (0, 250)             # angle, length
HOUR = (WORKED_TO, 180)       # the hour hand ends the shaded part
HAND_WIDTH = 40
HUB_RADIUS = 30
SHADOW_OFFSET = 14
SHADOW_SOFTNESS = 28
SHADOW_STRENGTH = 0.22


def circle(x, y, radius):
    return math.hypot(x - CENTRE[0], y - CENTRE[1]) - radius


def direction(degrees):
    """A unit vector pointing at `degrees` clockwise from twelve o'clock."""
    a = math.radians(degrees)
    return math.sin(a), -math.cos(a)


def hand(x, y, degrees, length):
    """Signed distance to a hand: a capsule from the centre outwards."""
    dx, dy = direction(degrees)
    px, py = x - CENTRE[0], y - CENTRE[1]
    t = min(max(px * dx + py * dy, 0.0), length)
    return math.hypot(px - dx * t, py - dy * t) - HAND_WIDTH / 2


def worked(x, y):
    """Signed distance to the shaded wedge from twelve to `WORKED_TO`, which is
    under half a turn and so the meeting of a disc and two half-planes."""
    px, py = x - CENTRE[0], y - CENTRE[1]
    after_twelve = -px
    dx, dy = direction(WORKED_TO)
    before_end = -(px * dy - py * dx)
    return max(circle(x, y, WORKED_RADIUS), after_twelve, before_end)


def coverage(distance):
    """How much of a pixel a shape covers, from its distance at the pixel centre."""
    return min(1.0, max(0.0, 0.5 - distance))


def blurred(distance, softness):
    """A shape's edge seen through a Gaussian blur."""
    return 0.5 * math.erfc(distance / (softness * math.sqrt(2)))


def mix(under, over, amount):
    return tuple(a + (b - a) * amount for a, b in zip(under, over))


def colour_at(x, y):
    colour = mix(FIELD_TOP, FIELD_BOTTOM, y / SIZE)
    shadow = SHADOW_STRENGTH * blurred(circle(x, y - SHADOW_OFFSET, FACE_RADIUS), SHADOW_SOFTNESS)
    colour = mix(colour, (0, 0, 0), shadow)
    colour = mix(colour, FACE, coverage(circle(x, y, FACE_RADIUS)))
    colour = mix(colour, WORKED, coverage(worked(x, y)))
    colour = mix(colour, ORANGE, coverage(hand(x, y, *HOUR)))
    colour = mix(colour, NAVY, coverage(hand(x, y, *MINUTE)))
    return mix(colour, NAVY, coverage(circle(x, y, HUB_RADIUS)))


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


# The iPhone app's icon, and the Apple Watch app's: the same artwork, which
# watchOS masks to a circle. The face sits well inside the circle already.
OUTPUTS = [
    "Hours/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    "HoursWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
]

if __name__ == "__main__":
    image = png(render())
    for relative in OUTPUTS:
        out = Path(__file__).resolve().parent.parent / relative
        out.write_bytes(image)
        print(f"wrote {out.relative_to(Path.cwd()) if out.is_relative_to(Path.cwd()) else out}")
