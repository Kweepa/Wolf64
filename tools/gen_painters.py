#!/usr/bin/env python3
"""
Generate compiled wall-height column painters (TechDesignDoc §4).

half_h 1..50: unrolled painters, no SMC.
half_h 51..75: shared Bresenham loop, no SMC either — only two 1-byte page
increments per row-advance (see below).

Writes generated/src/painters.asm: a painter_tbl .word dispatch table
(height -> painter_hNN, one indirect-jump vector per height) followed by
the routines themselves — see emit_tbl() for why the table comes first.

Entry for ALL heights: X = texx*16 + id, Y = column — set once by
paint_column (render.asm) and never touched again; there is no runtime
texture-id patch anywhere in this file any more.

TEX_HI/TEX_LO hold every (row, texx, id) texel pre-masked at build time:
TEX_HI + row*256,x = texel<<4 (lo nibble already 0), TEX_LO + row*256,x =
texel (hi nibble already 0). Both bases are page-aligned, so "row*256" is
purely a high-byte offset.

half_h 1..50 (compile-time row): each combine site already knows row_top/
row_bot, so it just emits `lda TEX_HI+row_top*256,x` / `ora TEX_LO+row_bot*256,x`
— no AND, no shift, no table selection.

half_h 51..75 (runtime row, Bresenham-stepped): row is not known until the
loop runs, so the two LDA sites' high-byte operands start at
`>TEX_HI/>TEX_LO + starting_row` (from near_tex0) and get `inc`'d by 1
(one page) whenever the Bresenham error carries — X still never changes.

Viewport letterbox: painters use cells 2..21 (20 cells = 40 chunky rows).
view_row0 is anchored so those cells land on screen rows 5..24 (bottom of
the 25-row display); rows 0..4 are reserved for the fat wolf UI.
Columns 0 and 39 are skipped in the cast/paint loops (38 columns).
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
OUT = Path(__file__).resolve().parents[1] / "generated" / "src" / "painters.asm"


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

		def flush_run() -> None:
			nonlocal run_val, run_n, run_start
			if run_val is not None and run_n:
				emit_run(code, run_val, run_start, run_n)
			run_val = None
			run_n = 0

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

			if kt == "sky":
				code.append("\tlda #$b0")
			elif kt == "floor":
				code.append("\tlda #$c0")
			else:
				code.append(f"\tlda TEX_HI + {tex_row(vt, h) * 256},x")

			if kb == "sky":
				code.append("\tora #$0b")
			elif kb == "floor":
				code.append("\tora #$0c")
			else:
				code.append(f"\tora TEX_LO + {tex_row(vb, h) * 256},x")

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

	distinct = sorted(set(tex0s))
	assert len(distinct) == 2, f"near_tex0 expected exactly 2 distinct values, got {distinct}"
	lo_val, hi_val = distinct
	split_y = tex0s.index(hi_val)
	assert tex0s[:split_y] == [lo_val] * split_y, "near_tex0 must be lo_val, then hi_val, no more transitions"
	assert tex0s[split_y:] == [hi_val] * (len(tex0s) - split_y), "near_tex0 must be lo_val, then hi_val, no more transitions"

	code.append("; ---- half_h 51..75: Bresenham near painter ----")
	code.append("; No SMC-computed pointer: TEX_HI/TEX_LO are page-per-row (row*256),")
	code.append("; X = texx*16+id stays untouched from entry (same as 1..50) and indexes")
	code.append("; within whichever row-page is currently selected. Advancing a row just")
	code.append("; INCs the LDA operand's high byte (row*256 -> +1 page) instead of a shift.")
	for h in range(NEAR_LO, MAX_HALF_H + 1):
		code.append(f"painter_h{h:02d}")
	code.append("painter_near")
	code += [
		"\tlda half_h",
		"\tsec",
		f"\tsbc #{NEAR_LO}",
		"\ttay\t\t\t\t; scratch only — X (texx*16+id) stays untouched",
		f"\t; near_tex0 is {lo_val} for y<{split_y}, {hi_val} for y>={split_y} — only 2",
		"\t; values, so branch straight to a build-time TEX_LO+tex0 constant instead",
		"\t; of a table+add; the skipped lda is eaten as a BIT-abs ($2c) operand so",
		"\t; there's no jmp needed to rejoin. TEX_HI's own high byte only ever needs",
		"\t; ONE bit flipped from TEX_LO's (they're a fixed, page-aligned 4K/$10-in-",
		"\t; the-high-byte apart, and tex0 < 16 never carries into that bit), so its",
		"\t; constant is a single eor away — no second cpy/bcc pair needed.",
		f"\tcpy #{split_y}",
		"\tbcc +",
		f"\tlda #(>TEX_LO)+{hi_val}",
		"\t!byte $2c",
		f"+\tlda #(>TEX_LO)+{lo_val}",
		"\tsta .pn_ld2+2",
		"\teor #(>TEX_LO) XOR (>TEX_HI)",
		"\tsta .pn_ld+2",
		"\tlda near_err0,y",
		"\tsta tmp5\t\t\t\t; bres err",
		"",
		"\tlda view_row2",
		"\tsta .pn_sta+1",
		"\tlda view_row2+1",
		"\tsta .pn_sta+2",
		"",
		"\tldy col",
		f"\tlda #{n_cells}",
		"\tsta tmp2\t\t\t\t; cell countdown",
		"\tclc\t\t\t\t; one-time: guarantees C=0 for the loop's first .pn_cell entry",
		"; No unconditional clc anywhere in the loop body. bcc .pn_s1/.pn_s2/",
		"; .pn_next taken means C=0 for free (that's what bcc tests) and nothing",
		"; between there and the next adc touches C (lda/ora/sta don't) — so the",
		"; taken path needs no clc before its adc. Each not-taken (row-advance /",
		"; page-advance) path gets its own clc so every path reaches the next",
		"; adc — including the top-of-loop one, next iteration — with C=0.",
		".pn_cell",
		".pn_ld",
		"\tlda TEX_HI,x\t\t\t; hi nibble already masked/positioned — no AND, no shift",
		"\tsta tmp0",
		"\tlda tmp5",
		"\tadc #8\t\t\t\t; C=0 guaranteed (first entry, or previous .pn_adv) — no clc",
		"\tcmp half_h",
		"\tbcc .pn_s1\t\t\t; taken -> C=0 already, no clc needed below",
		"\tsbc half_h",
		"\tinc .pn_ld+2\t\t\t; next tex row = next page",
		"\tinc .pn_ld2+2",
		"\tclc\t\t\t\t; not-taken path: force C=0 to match the taken path",
		".pn_s1",
		"\tsta tmp5",
		".pn_ld2",
		"\tlda TEX_LO,x\t\t\t; lo nibble already masked/positioned — no AND, no shift",
		"\tora tmp0",
		".pn_sta",
		"\tsta $ffff,y\t\t\t; Y=column",
		"\tlda tmp5",
		"\tadc #8\t\t\t\t; C=0 guaranteed by both paths above — no clc",
		"\tcmp half_h",
		"\tbcc .pn_s2\t\t\t; taken -> C=0 already, no clc needed below",
		"\tsbc half_h",
		"\tinc .pn_ld+2",
		"\tinc .pn_ld2+2",
		"\tclc\t\t\t\t; not-taken path: force C=0 to match the taken path",
		".pn_s2",
		"\tsta tmp5",
		".pn_adv",
		"\tlda .pn_sta+1",
		"\tadc #40\t\t\t\t; C=0 guaranteed by both paths above — no clc",
		"\tsta .pn_sta+1",
		"\tbcc .pn_next\t\t\t; taken -> C=0 already, no clc needed below",
		"\tinc .pn_sta+2",
		"\tclc\t\t\t\t; not-taken path: force C=0 for the next iteration's top adc",
		".pn_next",
		"\tdec tmp2",
		"\tbne .pn_cell",
		"\trts",
		"",
		"near_err0",
	]
	for i in range(0, len(err0s), 16):
		chunk = err0s[i : i + 16]
		code.append("\t!byte " + ", ".join(f"${b:02x}" for b in chunk))
	code.append("")


def emit_tbl(code: list[str]) -> None:
	"""height -> painter_hNN dispatch, one .word per height. Emitted FIRST so
	painter_tbl lands exactly on PAINTERS (page-aligned): every entry's high
	byte is then the same constant (>PAINTERS), so paint_column's indirect
	jump (render.asm) only ever has to patch the low byte of its operand —
	and since offsets are 2*half_h (always even), that byte can never be
	$ff, so the 6502 JMP-indirect page-wrap bug can't bite either."""
	code.append("; height -> painter_hNN, first so this starts page-aligned (see above)")
	code.append("painter_tbl")
	code.append("\t!word 0")
	for h in range(1, MAX_HALF_H + 1):
		code.append(f"\t!word painter_h{h:02d}")
	code.append("")


def main() -> None:
	code: list[str] = [
		"; AUTO-GENERATED by tools/gen_painters.py — do not edit",
		f"; Compiled height painters (half_h 1..{MAX_UNROLL} unrolled,",
		f"; {NEAR_LO}..{MAX_HALF_H} Bresenham loop) → back screen matrix",
		"; Entry: X = texx*16+id, Y = column; cells 2..21 only (38x40 chunky view)",
		"!zone painters",
		"",
	]

	emit_tbl(code)
	emit_unrolled(code)
	emit_near(code)

	code.append("painters_end")
	code.append("")
	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text("\n".join(code) + "\n", encoding="utf-8", newline="\n")

	n_near = MAX_HALF_H - NEAR_LO + 1
	print(f"Wrote {OUT}")
	print(f"Near bres tables: {n_near * 2} B (+ shared step loop)")


if __name__ == "__main__":
	main()
