#!/usr/bin/env python3
"""
Build C64 guard atlas from textures/guards/guards_sheet.png (VSWAP extract).

  1. Slice 20 frames from the 8×7 × 64px source sheet
  2. Scale uniformly so the tallest content height → 16px
  3. Remap to Pepto C64 palette minus black/white/cyan/green/yellow/light green;
     pink + greys only in the top 4 rows; ceiling dark grey never in top half
  4. Clip transparent edges
  5. Write only textures/guards/c64_16/guards_c64_16_sheet.png (5×4 contact sheet)

Walk A = source walk row 1; walk B = source walk row 2 (not row 3).
Hand edits go in guards_c64_sheet_edit.png — pack_enemies reads that file.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_walls import C64_PALETTE  # noqa: E402

# (name, sheet_row, sheet_col) on guards_sheet.png — 8 cols, stand then walk1–4 then combat
SELECTED: list[tuple[str, int, int]] = [
    *[(f"guard_s_{i}", 0, i - 1) for i in range(1, 6)],
    *[(f"guard_w1_{i}", 1, i - 1) for i in range(1, 6)],
    *[(f"guard_w2_{i}", 2, i - 1) for i in range(1, 6)],  # walk B = 2nd walk row
    ("guard_die_1", 5, 1),
    ("guard_pain_2", 5, 4),
    ("guard_dead", 5, 5),
    ("guard_shoot_2", 5, 7),
    ("guard_shoot_3", 6, 0),
]

SRC_COLS = 8
SRC_CELL = 64
OUT_COLS = 5
OUT_ROWS = 4

# Pepto indices excluded from guard remap: black, white, cyan, green, yellow, light green.
C64_EXCLUDE = {0, 1, 3, 5, 7, 13}
CEILING_GREY = 11  # sky $b — never in top half
FLOOR_GREY = 12  # floor $c — corpses sit on it, must not use
FACE_ONLY = {10, 11, 12, 15}
FACE_ROWS = 4
C64_GUARD_FACE = [i for i in range(16) if i not in C64_EXCLUDE | {CEILING_GREY}]
C64_GUARD_BODY = [i for i in range(16) if i not in C64_EXCLUDE | FACE_ONLY]


def nearest_c64_guard(rgb: tuple[int, int, int], allowed: list[int]) -> int:
    r, g, b = rgb
    best = allowed[0]
    best_d = 1 << 30
    for i in allowed:
        cr, cg, cb = C64_PALETTE[i]
        dr, dg, db = r - cr, g - cg, b - cb
        d = dr * dr * 2 + dg * dg * 4 + db * db * 3
        if d < best_d:
            best_d = d
            best = i
    return best


def opaque_bbox(img: Image.Image) -> tuple[int, int, int, int] | None:
    px = img.load()
    w, h = img.size
    xs: list[int] = []
    ys: list[int] = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 128:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def content_height(img: Image.Image) -> int:
    b = opaque_bbox(img)
    return 0 if b is None else b[3] - b[1]


def to_c64(
    img: Image.Image,
    *,
    ban_floor: bool = False,
    extra_allow: set[int] | frozenset[int] | None = None,
) -> Image.Image:
    """Remap opaque pixels to the guard Pepto subset.

    extra_allow: Pepto indices re-enabled on top of C64_EXCLUDE
    (e.g. cyan/green/yellow for Hans).
    """
    exclude = C64_EXCLUDE - set(extra_allow or ())
    face = [i for i in range(16) if i not in exclude | {CEILING_GREY}]
    body = [i for i in range(16) if i not in exclude | FACE_ONLY]
    px = img.load()
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    opx = out.load()
    for y in range(h):
        allowed = face if y < FACE_ROWS else body
        if ban_floor:
            allowed = [i for i in allowed if i != FLOOR_GREY]
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            i = nearest_c64_guard((r, g, b), allowed)
            cr, cg, cb = C64_PALETTE[i]
            opx[x, y] = (cr, cg, cb, 255)
    return out


def slice_src_cell(sheet: Image.Image, row: int, col: int) -> Image.Image:
    x0 = col * SRC_CELL
    y0 = row * SRC_CELL
    return sheet.crop((x0, y0, x0 + SRC_CELL, y0 + SRC_CELL)).convert("RGBA")


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    src_sheet = root / "textures" / "guards" / "guards_sheet.png"
    out_dir = root / "textures" / "guards" / "c64_16"
    out_dir.mkdir(parents=True, exist_ok=True)

    assert len(SELECTED) == OUT_COLS * OUT_ROWS, len(SELECTED)
    if not src_sheet.is_file():
        raise FileNotFoundError(src_sheet)

    src = Image.open(src_sheet)
    sw, sh = src.size
    if sw != SRC_COLS * SRC_CELL or sh < 7 * SRC_CELL:
        raise ValueError(f"expected {SRC_COLS}x7×{SRC_CELL} sheet, got {sw}x{sh}")

    frames: list[tuple[str, Image.Image, int]] = []
    for name, row, col in SELECTED:
        img = slice_src_cell(src, row, col)
        frames.append((name, img, content_height(img)))

    tallest = max(h for _, _, h in frames)
    scale = 16 / tallest
    print(f"tallest content = {tallest}px  scale = {scale:.6f}")

    finals: list[tuple[str, Image.Image]] = []
    for name, img, ch in frames:
        src_bbox = opaque_bbox(img)
        assert src_bbox is not None, name
        content = img.crop(src_bbox)
        nw = max(1, round(content.width * scale))
        nh = max(1, round(content.height * scale))
        scaled = content.resize((nw, nh), Image.NEAREST)
        c64 = to_c64(scaled, ban_floor=(name == "guard_dead"))
        bbox = opaque_bbox(c64)
        final = c64 if bbox is None else c64.crop(bbox)
        finals.append((name, final))
        print(f"{name:16} src_h={ch:2d} -> {final.size[0]}x{final.size[1]}")

    max_h = max(im.size[1] for _, im in finals)
    max_w = max(im.size[0] for _, im in finals)
    print(f"max output height = {max_h} (target 16)")

    sheet = Image.new("RGBA", (OUT_COLS * max_w, OUT_ROWS * max_h), (0, 0, 0, 0))
    for i, (name, im) in enumerate(finals):
        cx = (i % OUT_COLS) * max_w + (max_w - im.size[0]) // 2
        cy = (i // OUT_COLS) * max_h + (max_h - im.size[1]) // 2
        sheet.paste(im, (cx, cy), im)
    sheet_path = out_dir / "guards_c64_16_sheet.png"
    sheet.save(sheet_path)
    print(f"sheet {sheet.size[0]}x{sheet.size[1]} -> {sheet_path}")

    # Refresh walk-B row on the hand-edit sheet; keep other cells (muzzle flash).
    edit_path = out_dir / "guards_c64_sheet_edit.png"
    if edit_path.is_file():
        edit = Image.open(edit_path).convert("RGBA")
        if edit.size == sheet.size:
            cell_w = sheet.size[0] // OUT_COLS
            cell_h = sheet.size[1] // OUT_ROWS
            walk_b_row = 2
            y0 = walk_b_row * cell_h
            band = sheet.crop((0, y0, sheet.size[0], y0 + cell_h))
            edit.paste(band, (0, y0), band)
            edit.save(edit_path)
            print(f"updated walk-B row in {edit_path.name}")
        else:
            print(
                f"note: {edit_path.name} is {edit.size}, new sheet {sheet.size} — "
                "copy guards_c64_16_sheet.png over it if you want a full refresh"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
