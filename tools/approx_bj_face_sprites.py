#!/usr/bin/env python3
"""
Approximate refs/ui/bj_faces_sheet_clean.png with 5 hi-res 24×21 sprites.

Each source head is trimmed (drop top 1px + bottom 3px → 24×28). Locked
Pepto colours: red, light red, yellow, white. Black is the background
(pupils / holes). No dither.

  1× light red  top     hair and eyes
  2× red        free    neck shadow, features, hair detail
  1× yellow     bottom
  1× white      bottom

Writes:
  refs/ui/bj_faces_sprites.png            1:1 composite (6×4 of 24×28)
  refs/ui/bj_faces_sprites_x4.png         4× nearest
  refs/ui/bj_faces_sprites_compare_x4.png trimmed original | approx
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_walls import C64_PALETTE  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "refs" / "ui" / "bj_faces_sheet_clean.png"
OUT_DIR = ROOT / "refs" / "ui"

SHEET_COLS = 6
SHEET_ROWS = 4
SRC_W = 24
SRC_H = 32
TRIM_TOP = 1
TRIM_BOT = 3
FACE_W = 24
FACE_H = SRC_H - TRIM_TOP - TRIM_BOT  # 28
SPR_W = 24
SPR_H = 21
Y_MAX = FACE_H - SPR_H  # 7

COL_WHITE = 1
COL_RED = 2
COL_YELLOW = 7
COL_LTRED = 10
BG_LUMA = 24

# ltred + red_hi stay on the hair/eyes; yellow/white/red_lo on the chin.
TOP_Y = range(0, 4)
BOT_Y = range(4, Y_MAX + 1)

C64_NAMES = (
    "black",
    "white",
    "red",
    "cyan",
    "purple",
    "green",
    "blue",
    "yellow",
    "orange",
    "brown",
    "ltred",
    "dkgrey",
    "grey",
    "ltgreen",
    "ltblue",
    "ltgrey",
)


@dataclass
class Sprite:
    color: int
    y: int
    yrange: range
    mask: list[list[int]]


def dist2(rgb: tuple[int, int, int], idx: int) -> int:
    r, g, b = rgb
    cr, cg, cb = C64_PALETTE[idx]
    dr, dg, db = r - cr, g - cg, b - cb
    return dr * dr * 2 + dg * dg * 4 + db * db * 3


def nearest_in(rgb: tuple[int, int, int], indices: list[int]) -> int:
    best = indices[0]
    best_d = 1 << 30
    for i in indices:
        d = dist2(rgb, i)
        if d < best_d:
            best_d = d
            best = i
    return best


def is_pupil(rgb: tuple[int, int, int]) -> bool:
    """VGA iris is pure blue — not in the locked set; punch a hole."""
    r, g, b = rgb
    return b > r + 40 and b > g + 40


def is_bg(rgb: tuple[int, int, int]) -> bool:
    return rgb[0] + rgb[1] + rgb[2] < BG_LUMA or is_pupil(rgb)


def face_pixels(src: Image.Image, col: int, row: int) -> list[list[tuple[int, int, int]]]:
    px = src.load()
    ox, oy = col * SRC_W, row * SRC_H + TRIM_TOP
    return [
        [px[ox + x, oy + y][:3] for x in range(FACE_W)]
        for y in range(FACE_H)
    ]


def covering(sprites: list[Sprite], y: int) -> tuple[list[int], dict[int, int]]:
    pal = [0]
    spr_of: dict[int, int] = {}
    for i, s in enumerate(sprites):
        if s.y <= y < s.y + SPR_H and s.color not in spr_of:
            pal.append(s.color)
            spr_of[s.color] = i
    return pal, spr_of


def quantize(
    pix: list[list[tuple[int, int, int]]], sprites: list[Sprite]
) -> tuple[list[list[int]], list[Sprite]]:
    out = [[0] * FACE_W for _ in range(FACE_H)]
    for s in sprites:
        s.mask = [[0] * SPR_W for _ in range(SPR_H)]

    for y in range(FACE_H):
        pal, spr_of = covering(sprites, y)
        for x in range(FACE_W):
            rgb = pix[y][x]
            if is_bg(rgb):
                continue
            c = nearest_in(rgb, pal)
            out[y][x] = c
            if c:
                si = spr_of[c]
                sy = y - sprites[si].y
                if 0 <= sy < SPR_H:
                    sprites[si].mask[sy][x] = 1
    return out, sprites


def sse_img(
    pix: list[list[tuple[int, int, int]]], idx: list[list[int]]
) -> int:
    s = 0
    for y in range(FACE_H):
        for x in range(FACE_W):
            s += dist2(pix[y][x], idx[y][x])
    return s


def paint_indices(img: Image.Image, ox: int, oy: int, idx: list[list[int]]) -> None:
    px = img.load()
    for y in range(FACE_H):
        for x in range(FACE_W):
            px[ox + x, oy + y] = C64_PALETTE[idx[y][x]]


def make_sprites() -> list[Sprite]:
    return [
        Sprite(COL_LTRED, 0, TOP_Y, []),
        Sprite(COL_RED, 0, TOP_Y, []),
        Sprite(COL_RED, Y_MAX, BOT_Y, []),
        Sprite(COL_YELLOW, Y_MAX, BOT_Y, []),
        Sprite(COL_WHITE, Y_MAX, BOT_Y, []),
    ]


def approx_face(
    pix: list[list[tuple[int, int, int]]],
) -> tuple[list[list[int]], list[Sprite], int]:
    sprites = make_sprites()
    out, sprites = quantize(pix, sprites)
    best = sse_img(pix, out)

    for _pass in range(3):
        moved = False
        for i, s in enumerate(sprites):
            start_y = s.y
            local_best_y = start_y
            local_best = best
            for y in s.yrange:
                if y == start_y:
                    continue
                s.y = y
                trial, sprites = quantize(pix, sprites)
                e = sse_img(pix, trial)
                if e < local_best:
                    local_best = e
                    local_best_y = y
            s.y = local_best_y
            out, sprites = quantize(pix, sprites)
            best = sse_img(pix, out)
            if local_best_y != start_y:
                moved = True
        if not moved:
            break

    return out, sprites, best


def main() -> None:
    if not SRC.is_file():
        print(f"missing {SRC}", file=sys.stderr)
        sys.exit(1)

    src = Image.open(SRC).convert("RGB")
    if src.size != (SHEET_COLS * SRC_W, SHEET_ROWS * SRC_H):
        print(
            f"expected {SHEET_COLS * SRC_W}×{SHEET_ROWS * SRC_H}, got {src.size}",
            file=sys.stderr,
        )
        sys.exit(1)

    out_w, out_h = SHEET_COLS * FACE_W, SHEET_ROWS * FACE_H
    approx = Image.new("RGB", (out_w, out_h), (0, 0, 0))
    trimmed = Image.new("RGB", (out_w, out_h), (0, 0, 0))
    print(f"{'face':<8} {'SSE':>10}  sprites (col@y)")
    for row in range(SHEET_ROWS):
        for col in range(SHEET_COLS):
            pix = face_pixels(src, col, row)
            ox, oy = col * FACE_W, row * FACE_H
            tpx = trimmed.load()
            for y in range(FACE_H):
                for x in range(FACE_W):
                    tpx[ox + x, oy + y] = pix[y][x]
            idx, sprites, err = approx_face(pix)
            paint_indices(approx, ox, oy, idx)
            desc = " ".join(f"{C64_NAMES[s.color]}@{s.y}" for s in sprites)
            print(f"r{row}c{col:<4} {err:10d}  {desc}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    one = OUT_DIR / "bj_faces_sprites.png"
    x4 = OUT_DIR / "bj_faces_sprites_x4.png"
    cmp4 = OUT_DIR / "bj_faces_sprites_compare_x4.png"
    approx.save(one)
    approx.resize((out_w * 4, out_h * 4), Image.Resampling.NEAREST).save(x4)

    gap = 8
    compare = Image.new("RGB", (out_w * 8 + gap, out_h * 4), (0, 0, 0))
    compare.paste(
        trimmed.resize((out_w * 4, out_h * 4), Image.Resampling.NEAREST), (0, 0)
    )
    compare.paste(
        approx.resize((out_w * 4, out_h * 4), Image.Resampling.NEAREST),
        (out_w * 4 + gap, 0),
    )
    compare.save(cmp4)
    print(f"wrote {one}")
    print(f"wrote {x4}")
    print(f"wrote {cmp4}")


if __name__ == "__main__":
    main()
