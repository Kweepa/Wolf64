#!/usr/bin/env python3
"""
Convert textures/ui/uilayout.png → MCM bitmap + screen + colour RAM.

Outputs (textures/ui/):
  bitmap.bin   8000 bytes @ $6000
  screen.bin   2024 bytes — matrix A (1000) + 24-byte sprite-pointer pad + matrix B (1000)
               so B lands at $4400 (VIC gap $43E8–$43FF)
  colorram.bin 1000 bytes @ $d800
  uilayout_c64_preview.png

Packed HUD (5 char rows; row 3 cols 30–39 + row 4 = contiguous hidden code @ $64B0):
  rows 0–2 cols 32–39  face bank (4× 2×3, shared MCM; screen/colour 0 = hidden)
  row 3 cols 0–19      digits 0–9 flattened (upper cell, then lower)
  row 3 cols 20–29     digit 0–9 screen / colour LUT
  face/key ON attrs    emitted as src/ui_attr.inc (score overlay; not HUD cells)
  row 3 cols 30–39     zero attrs (joins bitmap row 4 code hole)

PNG source: digits at rows 3–4 cols 0–9; faces at rows 0–2 cols 32–39
(plus a face0 placeholder at cols 19–20 cleared from chrome).
Keys flank the face at row 2 cols 18 (gold) and 21 (silver) — bitmap stays;
visibility is toggled via colour attrs at runtime.
Live face dest is rows 0–2 col UI_COL_FACE (19).
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
GEN_UI_DIR = ROOT / "generated" / "textures" / "ui"

SRC_DIGIT_COL0 = 0
SRC_FACE_COL0 = 32
SRC_FACE_DEST_COL = 19  # placeholder cleared from chrome
N_FACES = 4
FACE_W_CELLS = 2
FACE_H_CELLS = 3

DST_DIGIT_COL0 = 0  # flattened: digit d at cols 2d (top) and 2d+1 (bot) on row 3
DST_FACE_COL0 = 32  # live chrome RHS, hidden via zero attrs
ATTR_DIGIT_ROW = 3
ATTR_DIGIT_COL0 = 20

# Live key cells in chrome (row 2, either side of face cols 19–20)
KEY_GOLD_COL = 18
KEY_SILVER_COL = 21
KEY_ROW = 2


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


def clear_cell(bitmap: bytearray, screen: bytearray, colorram: bytearray, cx: int, cy: int) -> None:
    write_bitmap_cell(bitmap, cx, cy, bytes(8))
    screen[cy * 40 + cx] = 0
    colorram[cy * 40 + cx] = 0


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

    # Live face dest is blitted at runtime; leave source bank bitmap, hide via attrs.
    for cy in range(FACE_H_CELLS):
        for dx in range(FACE_W_CELLS):
            clear_cell(bitmap, screen, colorram, SRC_FACE_DEST_COL + dx, cy)

    # Keys: keep bitmap, stash ON attrs, hide in live chrome (attrs=0).
    key_gold_scr = screen[KEY_ROW * 40 + KEY_GOLD_COL]
    key_gold_col = colorram[KEY_ROW * 40 + KEY_GOLD_COL]
    key_sil_scr = screen[KEY_ROW * 40 + KEY_SILVER_COL]
    key_sil_col = colorram[KEY_ROW * 40 + KEY_SILVER_COL]
    screen[KEY_ROW * 40 + KEY_GOLD_COL] = 0
    colorram[KEY_ROW * 40 + KEY_GOLD_COL] = 0
    screen[KEY_ROW * 40 + KEY_SILVER_COL] = 0
    colorram[KEY_ROW * 40 + KEY_SILVER_COL] = 0
    print(
        f"keys: gold col{KEY_GOLD_COL} scr=${key_gold_scr:02x} col=${key_gold_col:x}; "
        f"silver col{KEY_SILVER_COL} scr=${key_sil_scr:02x} col=${key_sil_col:x} (start hidden)"
    )

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
        for dy in range(FACE_H_CELLS):
            for dx in range(FACE_W_CELLS):
                cols = cell_mcm_colors(src, SRC_FACE_COL0 + f * FACE_W_CELLS + dx, dy)
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

    # Glyph rows 3–4: clear. Row 3 cols 30–39 + row 4 stay zero (score overlay @ $64B0).
    for cy in range(3, 5):
        for cx in range(40):
            clear_cell(bitmap, screen, colorram, cx, cy)

    for d in range(10):
        top, bot = digit_bmp[d]
        write_bitmap_cell(bitmap, DST_DIGIT_COL0 + d * 2, 3, top)
        write_bitmap_cell(bitmap, DST_DIGIT_COL0 + d * 2 + 1, 3, bot)

    for f in range(N_FACES):
        for i, cols in enumerate(face_colors[f]):
            dy, dx = i // FACE_W_CELLS, i % FACE_W_CELLS
            data = pack_cell_mapped(cols, face_c01, face_c10, face_c11)
            write_bitmap_cell(bitmap, DST_FACE_COL0 + f * 2 + dx, dy, data)
            # Hidden source: zero attrs so four BJ heads are not visible on the HUD.
            screen[dy * 40 + DST_FACE_COL0 + f * 2 + dx] = 0
            colorram[dy * 40 + DST_FACE_COL0 + f * 2 + dx] = 0

    for d in range(10):
        scr, col = digit_attr[d]
        screen[ATTR_DIGIT_ROW * 40 + ATTR_DIGIT_COL0 + d] = scr
        colorram[ATTR_DIGIT_ROW * 40 + ATTR_DIGIT_COL0 + d] = col

    attr_inc = ROOT / "generated" / "src" / "ui_attr.inc"
    attr_inc.parent.mkdir(parents=True, exist_ok=True)
    attr_inc.write_text(
        "; Auto-generated by tools/gen_ui_bitmap.py — face/key ON attrs\n"
        f"UI_ATTR_FACE\t\t!byte ${face_scr:02x}\n"
        f"UI_COLR_FACE\t\t!byte ${face_col:02x}\n"
        f"UI_ATTR_KEY_GOLD\t!byte ${key_gold_scr:02x}\n"
        f"UI_COLR_KEY_GOLD\t!byte ${key_gold_col:02x}\n"
        f"UI_ATTR_KEY_SILVER\t!byte ${key_sil_scr:02x}\n"
        f"UI_COLR_KEY_SILVER\t!byte ${key_sil_col:02x}\n"
    )

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

    GEN_UI_DIR.mkdir(parents=True, exist_ok=True)
    (GEN_UI_DIR / "bitmap.bin").write_bytes(bitmap)
    (GEN_UI_DIR / "screen.bin").write_bytes(screen_both)
    (GEN_UI_DIR / "colorram.bin").write_bytes(colorram)

    prev = Image.new("RGB", (320, 40))
    ppx = prev.load()
    for cy in range(5):
        for cx in range(40):
            data = read_bitmap_cell(bitmap, cx, cy)
            scr = screen[cy * 40 + cx]
            col = colorram[cy * 40 + cx]
            if cy == 3 and cx < 20:
                d = cx // 2
                scr = screen[ATTR_DIGIT_ROW * 40 + ATTR_DIGIT_COL0 + d]
                col = colorram[ATTR_DIGIT_ROW * 40 + ATTR_DIGIT_COL0 + d]
            elif cy < 3 and DST_FACE_COL0 <= cx < DST_FACE_COL0 + N_FACES * FACE_W_CELLS:
                scr, col = face_scr, face_col
            # Preview keys as ON (live chrome starts hidden).
            elif cy == KEY_ROW and cx == KEY_GOLD_COL:
                scr, col = key_gold_scr, key_gold_col
            elif cy == KEY_ROW and cx == KEY_SILVER_COL:
                scr, col = key_sil_scr, key_sil_col
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
    prev.save(GEN_UI_DIR / "uilayout_c64_preview.png")

    print(
        f"Wrote bitmap.bin ({len(bitmap)}), screen.bin ({len(screen_both)}), "
        f"colorram.bin ({len(colorram)}), {attr_inc.name}"
    )
    print(
        f"faces: {N_FACES}×{FACE_W_CELLS*8}x{FACE_H_CELLS*8} hidden @ cols "
        f"{DST_FACE_COL0}–{DST_FACE_COL0 + N_FACES * FACE_W_CELLS - 1} rows 0–2; "
        f"digits flattened row 3 cols 0–19"
    )


if __name__ == "__main__":
    main()
