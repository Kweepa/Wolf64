#!/usr/bin/env python3
"""
Convert textures/ui/uilayout.png → MCM bitmap + screen + colour RAM.

Outputs (textures/ui/):
  bitmap.bin   8000 bytes @ $6000
  screen.bin   2024 bytes — matrix A (1000) + 24-byte sprite-pointer pad + matrix B (1000)
               so B lands at $4400 (VIC gap $43E8–$43FF)
  colorram.bin 1000 bytes @ $d800
  uilayout_c64_preview.png

Packed HUD (5 char rows; row 3 cols 30–39 + row 4 cols 10–39 = hidden code):
  rows 0–3             chrome from PNG (yellow BJ silhouette + keys)
  rows 3–4 cols 0–9    digit glyphs in place; screen/colour 0 = hidden
  key ON attrs         emitted as src/ui_attr.inc (score overlay; not HUD cells)
  row 3 cols 30–39     zero attrs (joins bitmap row 4 code hole)

PNG source: digits at rows 3–4 cols 0–9. Keys at row 3 cols 17 (gold) and 22
(silver) — bitmap stays; visibility is toggled via colour attrs at runtime.
Yellow face is baked into the bitmap; overlay is VIC sprites (not cells).
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
N_DIGITS = 10

# Live key cells in chrome (row 3, flanking the yellow chin)
KEY_GOLD_COL = 17
KEY_SILVER_COL = 22
KEY_ROW = 3


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

    for cy in range(5):
        for cx in range(40):
            data, scr, col = pack_cell(cell_mcm_colors(src, cx, cy))
            write_bitmap_cell(bitmap, cx, cy, data)
            screen[cy * 40 + cx] = scr
            colorram[cy * 40 + cx] = col

    # Digits stay on PNG rows 3–4 cols 0–9; hide via black attrs (keep bitmap).
    for cy in (3, 4):
        for cx in range(N_DIGITS):
            screen[cy * 40 + cx] = 0
            colorram[cy * 40 + cx] = 0

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

    # Row 3 cols 30–39 + row 4 cols 10–39: zero attrs for score overlay.
    for cx in range(30, 40):
        screen[3 * 40 + cx] = 0
        colorram[3 * 40 + cx] = 0
    for cx in range(10, 40):
        screen[4 * 40 + cx] = 0
        colorram[4 * 40 + cx] = 0

    attr_inc = ROOT / "generated" / "src" / "ui_attr.inc"
    attr_inc.parent.mkdir(parents=True, exist_ok=True)
    attr_inc.write_text(
        "; Auto-generated by tools/gen_ui_bitmap.py — key ON attrs\n"
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
            # Preview keys as ON (live chrome starts hidden).
            if cy == KEY_ROW and cx == KEY_GOLD_COL:
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
        f"digits hidden in place rows 3–4 cols 0–9; "
        f"keys row {KEY_ROW} cols {KEY_GOLD_COL}/{KEY_SILVER_COL}"
    )


if __name__ == "__main__":
    main()
