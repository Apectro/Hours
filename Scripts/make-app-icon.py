#!/usr/bin/env python3
"""Draws Hours' app icon.

A script rather than a checked-in binary nobody can edit: the mark is four
rules of a timesheet, one of them run long and picked out in amber — the day
that went over, which is the whole point of the app. Change the numbers below
and run it; the PNG is the output, not the source.

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
SUBSAMPLES = 4  # vertical oversampling, for edges that are not stepped

TOP = (0x17, 0x22, 0x4A)
BOTTOM = (0x2B, 0x4A, 0x93)
RULE = (0xF2, 0xF4, 0xF9)
OVER = (0xF0, 0xA8, 0x3C)

# left, right, colour — laid out top to bottom, evenly spaced.
BARS = [
    (224, 656, RULE),
    (224, 560, RULE),
    (224, 800, OVER),
    (224, 608, RULE),
]
BAR_HEIGHT = 96
BAR_GAP = 52


def bar_rows():
    """Vertical centres, with the stack centred in the canvas."""
    count = len(BARS)
    total = count * BAR_HEIGHT + (count - 1) * BAR_GAP
    top = (SIZE - total) / 2
    return [top + index * (BAR_HEIGHT + BAR_GAP) + BAR_HEIGHT / 2 for index in range(count)]


def coverage(row, centre, left, right):
    """How much of each pixel in `row` a pill-shaped bar covers, 0...1.

    The ends are semicircles, so at a given height the bar is inset by
    r - sqrt(r^2 - dy^2). Returned as (start, end, inset) rather than a list:
    the caller fills the span, and only the two edge pixels are fractional.
    """
    radius = BAR_HEIGHT / 2
    dy = abs(row - centre)
    if dy >= radius:
        return None
    inset = radius - math.sqrt(radius * radius - dy * dy)
    return left + inset, right - inset


def render():
    centres = bar_rows()
    rows = []
    for y in range(SIZE):
        # The ground, sampled once per row: a vertical gradient has no
        # horizontal variation to resolve.
        t = y / (SIZE - 1)
        ground = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))

        # Accumulated coverage per pixel, per bar colour.
        cover = [0.0] * SIZE
        colour = [None] * SIZE
        for step in range(SUBSAMPLES):
            sample = y + (step + 0.5) / SUBSAMPLES
            for (left, right, rgb), centre in zip(BARS, centres):
                span = coverage(sample, centre, left, right)
                if span is None:
                    continue
                start, end = span
                first, last = int(math.floor(start)), int(math.ceil(end))
                for x in range(max(0, first), min(SIZE, last)):
                    overlap = min(x + 1.0, end) - max(float(x), start)
                    if overlap <= 0:
                        continue
                    cover[x] += overlap / SUBSAMPLES
                    colour[x] = rgb

        row = bytearray()
        row.append(0)  # PNG filter type 0: none
        for x in range(SIZE):
            alpha = min(1.0, cover[x])
            if alpha <= 0 or colour[x] is None:
                row.extend(ground)
            else:
                row.extend(
                    round(ground[i] + (colour[x][i] - ground[i]) * alpha) for i in range(3)
                )
        rows.append(bytes(row))
    return b"".join(rows)


def chunk(kind, payload):
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))


def write(path):
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit truecolour, no alpha
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(render(), 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)
    return len(png)


if __name__ == "__main__":
    destination = Path(__file__).resolve().parent.parent / "Hours/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    size = write(destination)
    print(f"{destination.relative_to(Path.cwd()) if destination.is_relative_to(Path.cwd()) else destination} — {size:,} bytes")
