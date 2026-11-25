#!/usr/bin/env python3
"""Generate the Connect IQ launcher icon (60x60 RGBA PNG) without any
third-party imaging library.

The icon is a dark disc with a horizontal "beam" line running into a
target spot, echoing the ESS accelerator layout.
"""
import struct
import sys
import zlib

SIZE = 60
BG = (11, 31, 51, 255)        # dark navy disc
RING = (70, 120, 160, 255)    # rim
BEAM = (255, 176, 0, 255)     # amber beam
SPOT = (255, 255, 255, 255)   # target spot
CLEAR = (0, 0, 0, 0)


def build_pixels():
    c = (SIZE - 1) / 2.0
    radius = SIZE / 2.0 - 0.5
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            dx, dy = x - c, y - c
            dist = (dx * dx + dy * dy) ** 0.5
            if dist > radius:
                px = CLEAR
            elif dist > radius - 2.5:
                px = RING
            elif abs(dy) <= 2.0 and dx < 12:
                px = BEAM
            elif (dx - 14) ** 2 + dy * dy <= 25:
                px = SPOT
            else:
                px = BG
            row.extend(px)
        rows.append(bytes(row))
    return rows


def chunk(tag, payload):
    body = tag + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_png(path):
    rows = build_pixels()
    raw = b"".join(b"\x00" + r for r in rows)
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", header)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)
    return len(png)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "resources/drawables/launcher_icon.png"
    print("wrote %s (%d bytes, %dx%d)" % (out, write_png(out), SIZE, SIZE))
