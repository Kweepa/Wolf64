#!/usr/bin/env python3
"""Pack textures/Wolf_12.kla as the Koala MCM loading screen.

Koala layout is 10003 bytes: load address, 8000 bitmap, 1000 screen,
1000 colour, 1 background. Colour and background are masked to the low nybble.

splashc_data.bin → ACME splashc.asm prepends load $8000 and appends do_splash.
splash.prg      → $A000 bitmap, loaded after colour so it paints in already coloured.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_walls import C64_PALETTE  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
KLA = ROOT / "textures" / "Wolf_12.kla"
OUT_COL_BIN = ROOT / "generated" / "splashc_data.bin"
OUT_BMP = ROOT / "generated" / "splash.prg"
PREVIEW = ROOT / "generated" / "splash_preview.png"

LOAD_BMP = 0xA000
COLS = 40
ROWS = 25
BITMAP_SIZE = 8000
SCR_SIZE = 1000
COL_SIZE = 1000
# load address + bitmap + screen + colour + background
KLA_LEN = 2 + BITMAP_SIZE + SCR_SIZE + COL_SIZE + 1


def decode_preview(bmp: bytes, scr: bytes, col: bytes, bg: int) -> Image.Image:
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
	if not KLA.is_file():
		print(f"missing: {KLA}", file=sys.stderr)
		sys.exit(1)
	raw = KLA.read_bytes()
	if len(raw) != KLA_LEN:
		print(f"{KLA.name} expected {KLA_LEN} bytes, got {len(raw)}", file=sys.stderr)
		sys.exit(1)

	bmp = raw[2 : 2 + BITMAP_SIZE]
	scr = raw[2 + BITMAP_SIZE : 2 + BITMAP_SIZE + SCR_SIZE]
	col = bytes(b & 15 for b in raw[2 + BITMAP_SIZE + SCR_SIZE : KLA_LEN - 1])
	bg = raw[KLA_LEN - 1] & 15

	OUT_COL_BIN.parent.mkdir(parents=True, exist_ok=True)
	col_data = scr + col + bytes([bg])
	OUT_COL_BIN.write_bytes(col_data)
	OUT_BMP.write_bytes(struct.pack("<H", LOAD_BMP) + bmp)
	decode_preview(bmp, scr, col, bg).save(PREVIEW)
	print(f"wrote {OUT_COL_BIN.relative_to(ROOT)} data={len(col_data)} bg=${bg:02x}")
	print(f"wrote {OUT_BMP.relative_to(ROOT)} load=${LOAD_BMP:04x} data={len(bmp)}")
	print(f"wrote {PREVIEW.relative_to(ROOT)}")


if __name__ == "__main__":
	main()
