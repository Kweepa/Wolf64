#!/usr/bin/env python3
"""Generate Judd/Arndt SQTAB1..4 (2K) as a CBM PRG load @ $3800.

Matches src/mul.asm init_sqtabs table fill (ZP hi pointers stay in-game).
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

SQTAB_LOAD = 0x3800
SQTAB_SIZE = 0x800


def build_sqtab() -> bytes:
	"""Replicate the 6502 loops from init_sqtabs into a flat 2K buffer."""
	mem = bytearray(SQTAB_SIZE)

	def s1(i: int) -> int:
		return i

	def s2(i: int) -> int:
		return 0x200 + i

	def s3(i: int) -> int:
		return 0x400 + i

	def s4(i: int) -> int:
		return 0x600 + i

	mem[s3(0xFE)] = 0
	mem[s4(0xFE)] = 0

	y = 0xFF
	x = 0
	while True:
		# txa / lsr / clc / adc SQTAB3+$fe,x
		a = x >> 1
		s = a + mem[s3(0xFE + x)]
		a = s & 0xFF
		c = 1 if s > 0xFF else 0
		mem[s1(x)] = a
		mem[s3(0xFF + x)] = a
		mem[s3(y)] = a
		# lda #0 / adc SQTAB4+$fe,x
		s = 0 + mem[s4(0xFE + x)] + c
		a = s & 0xFF
		mem[s2(x)] = a
		mem[s4(0xFF + x)] = a
		mem[s4(y)] = a
		y = (y - 1) & 0xFF
		x = (x + 1) & 0xFF
		if x == 0:
			break

	# loop2: X starts at 0 after wrap
	while True:
		# txa / sec / ror  →  (x >> 1) | $80
		a = 0x80 | (x >> 1)
		# clc / adc SQTAB1+$ff,x
		s = a + mem[s1(0xFF + x)]
		a = s & 0xFF
		c = 1 if s > 0xFF else 0
		mem[s1(0x100 + x)] = a
		# lda #0 / adc SQTAB2+$ff,x
		s = 0 + mem[s2(0xFF + x)] + c
		mem[s2(0x100 + x)] = s & 0xFF
		x = (x + 1) & 0xFF
		if x == 0:
			break

	return bytes(mem)


def main() -> None:
	default_out = Path(__file__).resolve().parents[1] / "generated" / "sqtab.prg"
	ap = argparse.ArgumentParser(description="Generate sqtab.prg @ $3800")
	ap.add_argument("-o", "--output", default=str(default_out))
	args = ap.parse_args()

	data = build_sqtab()
	assert len(data) == SQTAB_SIZE
	out = Path(args.output)
	out.parent.mkdir(parents=True, exist_ok=True)
	out.write_bytes(struct.pack("<H", SQTAB_LOAD) + data)
	print(f"Wrote {out} ({SQTAB_SIZE} bytes @ ${SQTAB_LOAD:04X})")


if __name__ == "__main__":
	main()
