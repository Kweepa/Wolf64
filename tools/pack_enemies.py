#!/usr/bin/env python3
"""
Pack enemy C64 edit sheets into textures/enemies.bin + src/enemy_gfx.asm LUTs.

Reads (hand-edited) sheets — not the *_c64_16_sheet.png regenerations:

  textures/guards/c64_16/guards_c64_sheet_edit.png
  textures/dogs/c64_16/dogs_c64_sheet_edit.png
  textures/ss/c64_16/ss_c64_sheet_edit.png
  textures/hans/c64_16/hans_c64_sheet_edit.png

Blob is linked at SFX_BASE (copied from the bitmap load image at start).

Layout per frame (column-major 4bpp, nibble 0 = transparent):
  For x in 0..w-1:
    for y in 0..h-1 step 2:
      byte = (pix[y] << 4) | (pix[y+1] if y+1 < h else 0)

Frame order: guards (20), dogs (15), ss (20), hans (11).
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_walls import C64_PALETTE  # noqa: E402
from process_enemy_c64 import (  # noqa: E402
    DOG_COLS,
    DOG_ROWS,
    DOG_SELECTED,
    HANS_COLS,
    HANS_ROWS,
    HANS_SELECTED,
    SS_COLS,
    SS_ROWS,
    SS_SELECTED,
)
from process_guard_c64 import (  # noqa: E402
    OUT_COLS as GUARD_COLS,
    OUT_ROWS as GUARD_ROWS,
    SELECTED as GUARD_SELECTED,
)

RGB_TO_IDX = {rgb: i for i, rgb in enumerate(C64_PALETTE)}

SETS: list[tuple[str, Path, list[tuple[str, int, int]], int, int]] = [
    (
        "guards",
        Path("textures/guards/c64_16/guards_c64_sheet_edit.png"),
        GUARD_SELECTED,
        GUARD_COLS,
        GUARD_ROWS,
    ),
    (
        "dogs",
        Path("textures/dogs/c64_16/dogs_c64_sheet_edit.png"),
        DOG_SELECTED,
        DOG_COLS,
        DOG_ROWS,
    ),
    (
        "ss",
        Path("textures/ss/c64_16/ss_c64_sheet_edit.png"),
        SS_SELECTED,
        SS_COLS,
        SS_ROWS,
    ),
    (
        "hans",
        Path("textures/hans/c64_16/hans_c64_sheet_edit.png"),
        HANS_SELECTED,
        HANS_COLS,
        HANS_ROWS,
    ),
]


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


def frame_indices(img: Image.Image) -> tuple[int, int, list[int]]:
    """RGBA → (w, h, row-major indices; transparent → 0). Exact Pepto RGB only."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    out: list[int] = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                out.append(0)
            else:
                out.append(RGB_TO_IDX.get((r, g, b), 0) & 0x0F)
    return w, h, out


def pack_columns(w: int, h: int, row_major: list[int]) -> bytes:
    """Column-major 4bpp (two vertical texels per byte)."""
    blob = bytearray()
    for x in range(w):
        for y in range(0, h, 2):
            hi = row_major[y * w + x] & 0x0F
            lo = row_major[(y + 1) * w + x] & 0x0F if y + 1 < h else 0
            blob.append((hi << 4) | lo)
    return bytes(blob)


def pack_sheet(
    sheet_path: Path,
    selected: list[tuple[str, int, int]],
    cols: int,
    rows: int,
    blob: bytearray,
    widths: list[int],
    heights: list[int],
    offsets: list[int],
    names: list[str],
) -> None:
    if not sheet_path.is_file():
        raise FileNotFoundError(sheet_path)
    if len(selected) > cols * rows:
        raise ValueError(f"{sheet_path}: {len(selected)} frames > {cols}x{rows}")

    sheet = Image.open(sheet_path).convert("RGBA")
    sw, sh = sheet.size
    if sw % cols or sh % rows:
        raise ValueError(f"sheet {sw}x{sh} not divisible by {cols}x{rows} grid")
    cell_w = sw // cols
    cell_h = sh // rows
    print(f"\n{sheet_path.name}  {sw}x{sh}  cells {cell_w}x{cell_h}")

    for i, (name, _, _) in enumerate(selected):
        col = i % cols
        row = i // cols
        cell = sheet.crop(
            (col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)
        )
        bbox = opaque_bbox(cell)
        if bbox is None:
            raise ValueError(f"empty cell for {name} at col={col} row={row}")
        frame = cell.crop(bbox)
        w, h, idx = frame_indices(frame)
        off = len(blob)
        chunk = pack_columns(w, h, idx)
        blob.extend(chunk)
        widths.append(w)
        heights.append(h)
        offsets.append(off)
        names.append(name)
        print(f"  {name:16} {w:2}x{h:<2}  off={off:4}  bytes={len(chunk)}")


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    out_bin = root / "textures" / "enemies.bin"
    out_asm = root / "src" / "enemy_gfx.asm"

    blob = bytearray()
    widths: list[int] = []
    heights: list[int] = []
    offsets: list[int] = []
    names: list[str] = []
    bases: dict[str, int] = {}

    for set_name, rel, selected, cols, rows in SETS:
        bases[set_name] = len(names)
        pack_sheet(
            root / rel,
            selected,
            cols,
            rows,
            blob,
            widths,
            heights,
            offsets,
            names,
        )

    out_bin.write_bytes(blob)
    print(f"\nWrote {out_bin} ({len(blob)} bytes, {len(names)} frames)")

    eg_guard = bases["guards"]
    eg_dog = bases["dogs"]
    eg_ss = bases["ss"]
    eg_hans = bases["hans"]

    lines = [
        "; Auto-generated by tools/pack_enemies.py — do not edit",
        "!zone enemy_gfx",
        f"ENEMY_FRAME_COUNT = {len(names)}",
        "",
        f"EG_GUARD = {eg_guard}",
        f"EG_DOG = {eg_dog}",
        f"EG_SS = {eg_ss}",
        f"EG_HANS = {eg_hans}",
        "",
        "enemy_frm_w",
        "\t!byte " + ", ".join(str(w) for w in widths),
        "enemy_frm_h",
        "\t!byte " + ", ".join(str(h) for h in heights),
        "enemy_frm_off_lo",
        "\t!byte " + ", ".join(str(o & 0xFF) for o in offsets),
        "enemy_frm_off_hi",
        "\t!byte " + ", ".join(str((o >> 8) & 0xFF) for o in offsets),
        "",
        "; Guard / SS relative (add EG_GUARD or EG_SS)",
        "EF_STAND = 0",
        "EF_WALKA = 5",
        "EF_WALKB = 10",
        "EF_DIE = 15",
        "EF_PAIN = 16",
        "EF_DEAD = 17",
        "EF_SHOOT2 = 18",
        "EF_SHOOT3 = 19",
        "",
        "; Dog absolute indices",
        f"EF_DOG_WALKA = {eg_dog}",
        f"EF_DOG_WALKB = {eg_dog + 5}",
        f"EF_DOG_DIE = {eg_dog + 10}",
        f"EF_DOG_DIE3 = {eg_dog + 11}",
        f"EF_DOG_DEAD = {eg_dog + 12}",
        f"EF_DOG_JUMP1 = {eg_dog + 13}",
        f"EF_DOG_JUMP2 = {eg_dog + 14}",
        "",
        "; Hans absolute indices",
        f"EF_HANS_W1 = {eg_hans}",
        f"EF_HANS_W2 = {eg_hans + 1}",
        f"EF_HANS_W3 = {eg_hans + 2}",
        f"EF_HANS_W4 = {eg_hans + 3}",
        f"EF_HANS_SHOOT1 = {eg_hans + 4}",
        f"EF_HANS_SHOOT2 = {eg_hans + 5}",
        f"EF_HANS_SHOOT3 = {eg_hans + 6}",
        f"EF_HANS_DEAD = {eg_hans + 7}",
        f"EF_HANS_DIE1 = {eg_hans + 8}",
        f"EF_HANS_DIE2 = {eg_hans + 9}",
        f"EF_HANS_DIE3 = {eg_hans + 10}",
        "",
        "; enemy_gfx_data label lives in wolf64.asm (SFX load image → SFX_BASE)",
        "",
    ]
    out_asm.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out_asm}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
