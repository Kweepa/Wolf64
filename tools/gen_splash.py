#!/usr/bin/env python3
"""Pack textures/splashscreen_c64.png as Koala MCM splash (Pepto closest match).

320×200 RGB → VIC-II Pepto palette, 2px MCM pairs, 4 colours/cell (bg black + 3).
splashc_data.bin → ACME splashc.asm prepends load $4000 and appends do_splash.
splash.prg      → $6000 bitmap, loaded after colour so it paints in already coloured.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_walls import C64_PALETTE, nearest_c64  # noqa: E402
from gen_ui_bitmap import pack_cell  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PNG = ROOT / "textures" / "splashscreen_c64.png"
OUT_COL_BIN = ROOT / "generated" / "splashc_data.bin"
OUT_BMP = ROOT / "generated" / "splash.prg"
PREVIEW = ROOT / "generated" / "splash_preview.png"

LOAD_BMP = 0x6000
COLS = 40
ROWS = 25
BG = 0
BITMAP_SIZE = 8000
SCR_SIZE = 1000


def cell_mcm_colors(img: Image.Image, cx: int, cy: int) -> list[int]:
	"""One MCM colour per 2×1 hires pair (average RGB, then nearest Pepto)."""
	px = img.load()
	cols: list[int] = []
	for y in range(cy * 8, cy * 8 + 8):
		for x in range(cx * 8, cx * 8 + 8, 2):
			r1, g1, b1 = px[x, y][:3]
			r2, g2, b2 = px[x + 1, y][:3]
			cols.append(
				nearest_c64(((r1 + r2) // 2, (g1 + g2) // 2, (b1 + b2) // 2))
			)
	return cols


def decode_preview(
	bmp: list[int],
	scr: list[int],
	col: list[int],
	bg: int,
) -> Image.Image:
	im = Image.new("RGB", (COLS * 8, ROWS * 8), C64_PALETTE[bg])
	pp = im.load()
	for cy in range(ROWS):
		for cx in range(COLS):
			cell = cy * COLS + cx
			lut = (bg, scr[cell] >> 4, scr[cell] & 15, col[cell] & 15)
			base = cy * 320 + cx * 8
			for y in range(8):
				b = bmp[base + y]
				for p in range(4):
					bits = (b >> (6 - p * 2)) & 3
					c = C64_PALETTE[lut[bits]]
					xx = cx * 8 + p * 2
					yy = cy * 8 + y
					pp[xx, yy] = c
					pp[xx + 1, yy] = c
	return im


def main() -> None:
	if not PNG.is_file():
		print(f"missing: {PNG}", file=sys.stderr)
		sys.exit(1)
	src = Image.open(PNG).convert("RGB")
	if src.size != (COLS * 8, ROWS * 8):
		print(f"{PNG.name} expected {COLS * 8}×{ROWS * 8}, got {src.size}", file=sys.stderr)
		sys.exit(1)

	bmp = [0] * BITMAP_SIZE
	scr = [0] * SCR_SIZE
	col = [0] * SCR_SIZE
	for cy in range(ROWS):
		for cx in range(COLS):
			data, s, c = pack_cell(cell_mcm_colors(src, cx, cy))
			base = cy * 320 + cx * 8
			bmp[base : base + 8] = data
			scr[cy * COLS + cx] = s
			col[cy * COLS + cx] = c

	OUT_COL_BIN.parent.mkdir(parents=True, exist_ok=True)
	col_data = bytes(scr) + bytes(col) + bytes([BG])
	OUT_COL_BIN.write_bytes(col_data)
	OUT_BMP.write_bytes(struct.pack("<H", LOAD_BMP) + bytes(bmp))
	decode_preview(bmp, scr, col, BG).save(PREVIEW)
	print(f"wrote {OUT_COL_BIN.relative_to(ROOT)} data={len(col_data)}")
	print(f"wrote {OUT_BMP.relative_to(ROOT)} load=${LOAD_BMP:04x} data={len(bmp)}")
	print(f"wrote {PREVIEW.relative_to(ROOT)}")


if __name__ == "__main__":
	main()
