"""
Build every wedge asset: palette texture first, then one .glb per asset.

    python3 tools/blender/build_all.py            # everything
    python3 tools/blender/build_all.py crew drone # only some modules

Uses Blender as a Python module (pip install bpy). Each asset is rebuilt from
nothing with a fixed random seed, so the output is the same every run.
"""
import importlib
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "assets"))

import kit  # noqa: E402

MODULES = ["crew", "bridge", "drone", "alien", "carrier", "environment"]
SWATCH_PX = 8


def write_palette():
    """palette.png: 8 x 4 swatches of 8 px. Written without PIL."""
    w, h = kit.COLS * SWATCH_PX, kit.ROWS * SWATCH_PX
    rows = []
    for y in range(h):
        r = y // SWATCH_PX
        row = bytearray([0])
        for x in range(w):
            c = x // SWATCH_PX
            hexc = kit.PALETTE[r * kit.COLS + c][1].lstrip("#")
            row += bytes(int(hexc[i:i + 2], 16) for i in (0, 2, 4))
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(kit.PALETTE_PNG), exist_ok=True)
    with open(kit.PALETTE_PNG, "wb") as f:
        f.write(png)
    print(f"[kit] palette.png {w}x{h}")


def main():
    write_palette()
    names = sys.argv[1:] or MODULES
    for n in names:
        mod = importlib.import_module(n)
        mod.build()


if __name__ == "__main__":
    main()
