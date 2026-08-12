#!/usr/bin/env python3
"""
Convert textures/ui/uilayout.png → MCM bitmap + screen + colour RAM.

Outputs (textures/ui/):
  bitmap.bin   8000 bytes @ $6000
  screen.bin   2024 bytes — matrix A (1000) + 24-byte sprite-pointer pad + matrix B (1000)
               so B lands at $4400 (VIC gap $43E8–$43FF)
  colorram.bin 1000 bytes @ $d800
  uilayout_c64_preview.png

Glyph bank (rows 3–4), rearranged from PNG:
  cols 0–9   digits 0–9 (8×16)
  cols 10–25 faces 0–7 (16×16 each), shared MCM palette
  cols 26–39 empty bitmap; attr strip:
    row3 cols 30–39 = digit 0–9 screen / colour
    row4 col 26     = shared face screen / colour
"""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_walls import C64_PALETTE, nearest_c64  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
UI_DIR = ROOT / "textures" / "ui"
SRC_PNG = UI_DIR / "uilayout.png"

SRC_DIGIT_COL0 = 0
SRC_FACE_COL0 = 10
N_FACES = 8

DST_DIGIT_COL0 = 0
DST_FACE_COL0 = 10
ATTR_DIGIT_ROW = 3
ATTR_DIGIT_COL0 = 30
ATTR_FACE_ROW = 4
ATTR_FACE_COL = 26


def pack_cell_mapped(
    colors: list[int], c01: int, c10: int, c11: int
) -> bytes:
    """Pack 32 MCM colours with fixed 01/10/11 assignment (00 = black)."""

    def map_col(c: int) -> int:
        if c in (0, c01, c10, c11):
            return c
        rgb = C64_PALETTE[c]
        best, best_d = c01, 1 << 30
        for cand in (c01, c10, c11):
            cr, cg, cb = C64_PALETTE[cand]
            r, g, b = rgb
            d = (r - cr) ** 2 * 2 + (g - cg) ** 2 * 4 + (b - cb) ** 2 * 3
            if d < best_d:
                best_d = d
                best = cand
        return best

    bit_of = {0: 0, c01: 1, c10: 2, c11: 3}
    out = bytearray(8)
    for row in range(8):
        b = 0
        for p in range(4):
            c = map_col(colors[row * 4 + p])
            b = (b << 2) | bit_of.get(c, 0)
        out[row] = b
    return bytes(out)


def pack_cell(colors: list[int]) -> tuple[bytes, int, int]:
    """Auto palette: up to 3 non-black + bg black."""
    assert len(colors) == 32
    counts = Counter(c for c in colors if c != 0)
    top = [c for c, _ in counts.most_common(3)]
    while len(top) < 3:
        top.append(0)
    c01, c10, c11 = top[0], top[1], top[2]
    data = pack_cell_mapped(colors, c01, c10, c11)
    screen = ((c01 & 15) << 4) | (c10 & 15)
    colram = c11 & 15
    return data, screen, colram


def cell_mcm_colors(img: Image.Image, cx: int, cy: int) -> list[int]:
    px = img.load()
    cols: list[int] = []
    for y in range(cy * 8, cy * 8 + 8):
        for x in range(cx * 8, cx * 8 + 8, 2):
            cols.append(nearest_c64(px[x, y]))
    return cols


def write_bitmap_cell(bitmap: bytearray, cx: int, cy: int, data: bytes) -> None:
    off = cy * 320 + cx * 8
    bitmap[off : off + 8] = data


def read_bitmap_cell(bitmap: bytes | bytearray, cx: int, cy: int) -> bytes:
    off = cy * 320 + cx * 8
    return bytes(bitmap[off : off + 8])


def main() -> None:
    if not SRC_PNG.is_file():
        print(f"missing {SRC_PNG}", file=sys.stderr)
        sys.exit(1)

    src = Image.open(SRC_PNG).convert("RGB")
    if src.size != (320, 40):
        print(f"expected 320×40, got {src.size}", file=sys.stderr)
        sys.exit(1)

    bitmap = bytearray(8000)
    screen = bytearray(1000)
    colorram = bytearray(1000)

    for cy in range(3):
        for cx in range(40):
            data, scr, col = pack_cell(cell_mcm_colors(src, cx, cy))
            write_bitmap_cell(bitmap, cx, cy, data)
            screen[cy * 40 + cx] = scr
            colorram[cy * 40 + cx] = col

    digit_bmp: list[tuple[bytes, bytes]] = []
    digit_attr: list[tuple[int, int]] = []
    for d in range(10):
        cx = SRC_DIGIT_COL0 + d
        top, s0, c0 = pack_cell(cell_mcm_colors(src, cx, 3))
        bot, _s1, _c1 = pack_cell(cell_mcm_colors(src, cx, 4))
        digit_bmp.append((top, bot))
        digit_attr.append((s0, c0))

    face_colors: list[list[list[int]]] = []
    all_face_px: list[int] = []
    for f in range(N_FACES):
        cells = []
        for dy in range(2):
            for dx in range(2):
                cols = cell_mcm_colors(src, SRC_FACE_COL0 + f * 2 + dx, 3 + dy)
                cells.append(cols)
                all_face_px.extend(cols)
        face_colors.append(cells)

    counts = Counter(c for c in all_face_px if c != 0)
    top = [c for c, _ in counts.most_common(3)]
    while len(top) < 3:
        top.append(0)
    face_c01, face_c10, face_c11 = top[0], top[1], top[2]
    face_scr = ((face_c01 & 15) << 4) | (face_c10 & 15)
    face_col = face_c11 & 15
    print(
        f"shared face palette: 01=${face_c01:x} 10=${face_c10:x} 11=${face_c11:x} "
        f"screen=${face_scr:02x} col=${face_col:x}"
    )

    for cy in range(3, 5):
        for cx in range(40):
            write_bitmap_cell(bitmap, cx, cy, bytes(8))
            screen[cy * 40 + cx] = 0
            colorram[cy * 40 + cx] = 0

    for d in range(10):
        cx = DST_DIGIT_COL0 + d
        top, bot = digit_bmp[d]
        write_bitmap_cell(bitmap, cx, 3, top)
        write_bitmap_cell(bitmap, cx, 4, bot)

    for f in range(N_FACES):
        for i, cols in enumerate(face_colors[f]):
            dy, dx = i // 2, i % 2
            data = pack_cell_mapped(cols, face_c01, face_c10, face_c11)
            write_bitmap_cell(
                bitmap, DST_FACE_COL0 + f * 2 + dx, 3 + dy, data
            )

    for d in range(10):
        scr, col = digit_attr[d]
        screen[ATTR_DIGIT_ROW * 40 + ATTR_DIGIT_COL0 + d] = scr
        colorram[ATTR_DIGIT_ROW * 40 + ATTR_DIGIT_COL0 + d] = col

    screen[ATTR_FACE_ROW * 40 + ATTR_FACE_COL] = face_scr
    colorram[ATTR_FACE_ROW * 40 + ATTR_FACE_COL] = face_col

    for cy in range(5, 25):
        for cx in range(40):
            cell = bytearray(8)
            for y in range(4):
                cell[y] = 0x55
            for y in range(4, 8):
                cell[y] = 0xAA
            write_bitmap_cell(bitmap, cx, cy, bytes(cell))
            screen[cy * 40 + cx] = 0
            colorram[cy * 40 + cx] = 0

    # A | 24-byte VIC sprite-pointer gap | B  → B starts at $4400
    screen_both = bytes(screen) + bytes(24) + bytes(screen)

    UI_DIR.mkdir(parents=True, exist_ok=True)
    (UI_DIR / "bitmap.bin").write_bytes(bitmap)
    (UI_DIR / "screen.bin").write_bytes(screen_both)
    (UI_DIR / "colorram.bin").write_bytes(colorram)

    prev = Image.new("RGB", (320, 40))
    ppx = prev.load()
    for cy in range(5):
        for cx in range(40):
            data = read_bitmap_cell(bitmap, cx, cy)
            scr = screen[cy * 40 + cx]
            col = colorram[cy * 40 + cx]
            # Glyph cols use strip attrs for preview
            if cy >= 3 and cx < 10:
                scr = screen[ATTR_DIGIT_ROW * 40 + ATTR_DIGIT_COL0 + cx]
                col = colorram[ATTR_DIGIT_ROW * 40 + ATTR_DIGIT_COL0 + cx]
            elif cy >= 3 and 10 <= cx < 26:
                scr = face_scr
                col = face_col
            pal = [
                C64_PALETTE[0],
                C64_PALETTE[(scr >> 4) & 15],
                C64_PALETTE[scr & 15],
                C64_PALETTE[col & 15],
            ]
            for row in range(8):
                b = data[row]
                for p in range(4):
                    bit = (b >> (6 - p * 2)) & 3
                    rgb = pal[bit]
                    x0 = cx * 8 + p * 2
                    y0 = cy * 8 + row
                    ppx[x0, y0] = rgb
                    ppx[x0 + 1, y0] = rgb
    prev.save(UI_DIR / "uilayout_c64_preview.png")

    print(
        f"Wrote bitmap.bin ({len(bitmap)}), screen.bin ({len(screen_both)}), "
        f"colorram.bin ({len(colorram)})"
    )


if __name__ == "__main__":
    main()
