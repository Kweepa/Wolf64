#!/usr/bin/env python3
"""
Generate compiled wall-height column painters (TechDesignDoc §4).

half_h 1..50: unrolled SMC painters.
half_h 51..75: shared loop + baked 1-byte/cell texel-row recipes (top<<4|bot).

Writes src/painters.asm only. Jump/SMC tables come from make_painter_tables.py
after painters.bin is assembled.

Entry: X = texx*8, Y = column. Stores go to (view_rowN),y — back screen matrix.

Viewport letterbox: only cells 2..21 (20 cells = 40 chunky rows). Cells 0..1 and
22..23 are a static border (see fill_view_border). Columns 0 and 39 are skipped
in the cast/paint loops (38 columns).
"""

from __future__ import annotations

from pathlib import Path

SKY = 0xBB
FLOOR = 0xCC
CELL_LO = 2				# inclusive
CELL_HI = 22				# exclusive → cells 2..21
HALF_VIEW = 48
MAX_UNROLL = 50
MAX_HALF_H = 75
NEAR_LO = 51
OUT = Path(__file__).resolve().parents[1] / "src" / "painters.asm"


def tex_row(v: int, h: int) -> int:
	v0 = 24 - h
	t = ((v - v0) * 8) // h
	if t < 0:
		return 0
	if t > 15:
		return 15
	return t


def kind(v: int, h: int) -> str:
	v0 = 24 - h
	v1 = 24 + h
	if v < max(0, v0):
		return "sky"
	if v >= min(HALF_VIEW, v1):
		return "floor"
	return "wall"


def emit_run(lines: list[str], value: int, start: int, count: int) -> None:
	if count <= 0:
		return
	lines.append(f"\tlda #${value:02x}")
	for i in range(count):
		lines.append(f"\tsta (view_row{start + i}),y")


def emit_unrolled(code: list[str]) -> None:
	for h in range(1, MAX_UNROLL + 1):
		label = f"painter_h{h:02d}"
		code.append(f"; ---- half_h = {h} ----")
		code.append(label)

		run_val: int | None = None
		run_n = 0
		run_start = 0
		cell_i = 0

		def flush_run() -> None:
			nonlocal run_val, run_n, run_start
			if run_val is not None and run_n:
				emit_run(code, run_val, run_start, run_n)
			run_val = None
			run_n = 0

		def tex_lda(byte_off: int) -> None:
			nonlocal cell_i
			pl = f"smc_h{h:02d}_{cell_i}"
			cell_i += 1
			code.append(f"{pl}")
			code.append(f"\tlda TEXTURES + {byte_off},x")

		for c in range(CELL_LO, CELL_HI):
			vt, vb = 2 * c, 2 * c + 1
			kt, kb = kind(vt, h), kind(vb, h)

			if kt == "sky" and kb == "sky":
				if run_val == SKY:
					run_n += 1
				else:
					flush_run()
					run_val, run_n, run_start = SKY, 1, c
				continue
			if kt == "floor" and kb == "floor":
				if run_val == FLOOR:
					run_n += 1
				else:
					flush_run()
					run_val, run_n, run_start = FLOOR, 1, c
				continue

			flush_run()

			if kt == "wall" and kb == "wall":
				tr_t, tr_b = tex_row(vt, h), tex_row(vb, h)
				if (
					tr_t == (tr_b ^ 1)
					and (tr_t >> 1) == (tr_b >> 1)
					and (tr_t & 1) == 0
				):
					tex_lda(tr_t >> 1)
					code.append(f"\tsta (view_row{c}),y")
					continue

			if kt == "sky":
				code.append("\tlda #$b0")
				code.append("\tsta tmp0")
			elif kt == "floor":
				code.append("\tlda #$c0")
				code.append("\tsta tmp0")
			else:
				tr = tex_row(vt, h)
				tex_lda(tr >> 1)
				if tr & 1:
					code.append("\tand #$0f")
					code.append("\tasl")
					code.append("\tasl")
					code.append("\tasl")
					code.append("\tasl")
				else:
					code.append("\tand #$f0")
				code.append("\tsta tmp0")

			if kb == "sky":
				code.append("\tlda tmp0")
				code.append("\tora #$0b")
			elif kb == "floor":
				code.append("\tlda tmp0")
				code.append("\tora #$0c")
			else:
				tr = tex_row(vb, h)
				tex_lda(tr >> 1)
				if tr & 1:
					code.append("\tand #$0f")
				else:
					code.append("\tlsr")
					code.append("\tlsr")
					code.append("\tlsr")
					code.append("\tlsr")
				code.append("\tora tmp0")

			code.append(f"\tsta (view_row{c}),y")

		flush_run()
		code.append("\trts")
		code.append("")


def near_bres_init(h: int) -> tuple[int, int]:
	"""tex_row / err at first drawn chunky row (v=4), matching tex_row()."""
	delta = 4 - (24 - h)  # h - 20
	product = delta * 8
	return product // h, product % h


def emit_near(code: list[str]) -> None:
	"""Bresenham V-step near painter: stripe ptr once, +8/err per chunky row."""
	n_cells = CELL_HI - CELL_LO
	tex0s: list[int] = []
	err0s: list[int] = []
	for h in range(NEAR_LO, MAX_HALF_H + 1):
		t0, e0 = near_bres_init(h)
		tex0s.append(t0)
		err0s.append(e0)
		tex, err = t0, e0
		for v in range(4, 44):
			assert tex == tex_row(v, h), (h, v, tex, tex_row(v, h))
			err += 8
			if err >= h:
				err -= h
				tex += 1

	code.append("; ---- half_h 51..75: Bresenham near painter ----")
	code.append("; stripe = tex_ptr+texx*8 once; each chunky row: sample, err+=8,")
	code.append("; advance tex when err>=half_h")
	for h in range(NEAR_LO, MAX_HALF_H + 1):
		code.append(f"painter_h{h:02d}")
	code.append("painter_near")
	code += [
		"\tstx tmp2\t\t\t\t; texx*8",
		"\tclc",
		"\tlda tex_ptr_l",
		"\tadc tmp2",
		"\tsta .pn_ld+1\t\t\t; stripe base once/column",
		"\tlda tex_ptr_h",
		"\tadc #0",
		"\tsta .pn_ld+2",
		"",
		"\tlda half_h",
		"\tsec",
		f"\tsbc #{NEAR_LO}",
		"\ttax",
		"\tlda near_tex0,x",
		"\tsta tmp4\t\t\t\t; tex_row",
		"\tlda near_err0,x",
		"\tsta tmp5\t\t\t\t; bres err",
		"",
		"\tlda view_row2",
		"\tsta .pn_sta+1",
		"\tlda view_row2+1",
		"\tsta .pn_sta+2",
		"",
		f"\tlda #{n_cells}",
		"\tsta tmp2\t\t\t\t; cell countdown (X used by sample)",
		".pn_cell",
		"\tjsr .pn_sample",
		"\tasl",
		"\tasl",
		"\tasl",
		"\tasl",
		"\tsta tmp0",
		"\tlda tmp5",
		"\tclc",
		"\tadc #8",
		"\tcmp half_h",
		"\tbcc .pn_s1",
		"\tsbc half_h",
		"\tsta tmp5",
		"\tinc tmp4",
		"\tjmp .pn_b",
		".pn_s1",
		"\tsta tmp5",
		".pn_b",
		"\tjsr .pn_sample",
		"\tora tmp0",
		".pn_sta",
		"\tsta $ffff,y\t\t\t; Y=column",
		"\tlda tmp5",
		"\tclc",
		"\tadc #8",
		"\tcmp half_h",
		"\tbcc .pn_s2",
		"\tsbc half_h",
		"\tsta tmp5",
		"\tinc tmp4",
		"\tjmp .pn_adv",
		".pn_s2",
		"\tsta tmp5",
		".pn_adv",
		"\tclc",
		"\tlda .pn_sta+1",
		"\tadc #40",
		"\tsta .pn_sta+1",
		"\tbcc .pn_next",
		"\tinc .pn_sta+2",
		".pn_next",
		"\tdec tmp2",
		"\tbne .pn_cell",
		"\trts",
		"",
		"; tmp4 → A color nibble. Keeps Y. Clobbers X,tmp1.",
		".pn_sample",
		"\tlda tmp4",
		"\tlsr",
		"\ttax",
		".pn_ld",
		"\tlda $ffff,x",
		"\tsta tmp1",
		"\tlda tmp4",
		"\tand #1",
		"\tbne .pn_odd",
		"\tlda tmp1",
		"\tlsr",
		"\tlsr",
		"\tlsr",
		"\tlsr",
		"\trts",
		".pn_odd",
		"\tlda tmp1",
		"\tand #$0f",
		"\trts",
		"",
		"near_tex0",
	]
	for i in range(0, len(tex0s), 16):
		chunk = tex0s[i : i + 16]
		code.append("\t!byte " + ", ".join(f"${b:02x}" for b in chunk))
	code.append("near_err0")
	for i in range(0, len(err0s), 16):
		chunk = err0s[i : i + 16]
		code.append("\t!byte " + ", ".join(f"${b:02x}" for b in chunk))
	code.append("")


def main() -> None:
	code: list[str] = [
		"; AUTO-GENERATED by tools/gen_painters.py — do not edit",
		f"; Compiled height painters (half_h 1..{MAX_UNROLL} unrolled,",
		f"; {NEAR_LO}..{MAX_HALF_H} Bresenham loop) → back screen matrix",
		"; Entry: X = texx*8, Y = column; cells 2..21 only (38x40 chunky view)",
		"!zone painters",
		"",
	]

	emit_unrolled(code)
	emit_near(code)

	code.append("painters_end")
	code.append("")
	OUT.write_text("\n".join(code) + "\n", encoding="utf-8", newline="\n")

	n_near = MAX_HALF_H - NEAR_LO + 1
	print(f"Wrote {OUT}")
	print(f"Near bres tables: {n_near * 2} B (+ shared step loop)")


if __name__ == "__main__":
	main()
