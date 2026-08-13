#!/usr/bin/env python3
"""
Build C64 enemy atlases (max 16px tall, variable width, Pepto) from VSWAP sheets.

  guards — same 20 frames as process_guard_c64 (5×4)
  dogs   — purple-outlined cells on dogs_sheet.png (15 frames → 5×3)
  ss     — same frame picks as guards (20 frames → 5×4)
  hans   — all 11 Hans frames (4×3, last cell empty)

Writes textures/<set>/c64_16/<set>_c64_16_sheet.png and, if missing,
<set>_c64_sheet_edit.png for hand edits before packing.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from process_guard_c64 import (  # noqa: E402
    OUT_COLS as GUARD_COLS,
    OUT_ROWS as GUARD_ROWS,
    SELECTED as GUARD_SELECTED,
    SRC_CELL,
    SRC_COLS,
    content_height,
    opaque_bbox,
    slice_src_cell,
    to_c64,
)

# Purple-outlined on dogs_sheet: walk1/2 angles 1–5, die_1, die_3, dead, jump_1/2.
DOG_SELECTED: list[tuple[str, int, int]] = [
    *[(f"dog_w1_{i}", 0, i - 1) for i in range(1, 6)],
    *[(f"dog_w2_{i}", 1, i - 1) for i in range(1, 6)],
    ("dog_die_1", 4, 0),
    ("dog_die_3", 4, 2),
    ("dog_dead", 4, 3),
    ("dog_jump_1", 4, 4),
    ("dog_jump_2", 4, 5),
]
DOG_COLS, DOG_ROWS = 5, 3

# Same layout / picks as process_guard_c64.SELECTED on ss_sheet.png.
SS_SELECTED: list[tuple[str, int, int]] = [
    *[(f"ss_s_{i}", 0, i - 1) for i in range(1, 6)],
    *[(f"ss_w1_{i}", 1, i - 1) for i in range(1, 6)],
    *[(f"ss_w2_{i}", 2, i - 1) for i in range(1, 6)],
    ("ss_die_1", 5, 1),
    ("ss_pain_2", 5, 4),
    ("ss_dead", 5, 5),
    ("ss_shoot_2", 5, 7),
    ("ss_shoot_3", 6, 0),
]
SS_COLS, SS_ROWS = 5, 4

# All Hans frames in WL order on hans_sheet.png (8-col source).
HANS_SELECTED: list[tuple[str, int, int]] = [
    ("hans_w1", 0, 0),
    ("hans_w2", 0, 1),
    ("hans_w3", 0, 2),
    ("hans_w4", 0, 3),
    ("hans_shoot_1", 0, 4),
    ("hans_shoot_2", 0, 5),
    ("hans_shoot_3", 0, 6),
    ("hans_dead", 0, 7),
    ("hans_die_1", 1, 0),
    ("hans_die_2", 1, 1),
    ("hans_die_3", 1, 2),
]
HANS_COLS, HANS_ROWS = 4, 3  # last cell empty

# Hand-drawn selection marks on dogs_sheet.png (not part of the sprite).
DOG_MARK_RGB = (107, 94, 181)


def strip_mark_color(img: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
    """Make annotation pixels transparent so they don't affect scale/bbox."""
    out = img.copy()
    px = out.load()
    w, h = out.size
    tr, tg, tb = rgb
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 128 and (r, g, b) == (tr, tg, tb):
                px[x, y] = (0, 0, 0, 0)
    return out


def process_set(
    *,
    name: str,
    src_sheet: Path,
    out_dir: Path,
    selected: list[tuple[str, int, int]],
    out_cols: int,
    out_rows: int,
    src_rows: int,
    ban_floor_names: set[str],
    strip_rgb: tuple[int, int, int] | None = None,
    refresh_edit: bool = False,
    extra_allow: set[int] | frozenset[int] | None = None,
) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    if not src_sheet.is_file():
        raise FileNotFoundError(src_sheet)
    if len(selected) > out_cols * out_rows:
        raise ValueError(f"{name}: {len(selected)} frames > {out_cols}x{out_rows}")

    src = Image.open(src_sheet)
    sw, sh = src.size
    if sw != SRC_COLS * SRC_CELL or sh < src_rows * SRC_CELL:
        raise ValueError(
            f"{name}: expected {SRC_COLS}x{src_rows}×{SRC_CELL} sheet, got {sw}x{sh}"
        )

    frames: list[tuple[str, Image.Image, int]] = []
    for frame_name, row, col in selected:
        img = slice_src_cell(src, row, col)
        if strip_rgb is not None:
            img = strip_mark_color(img, strip_rgb)
        frames.append((frame_name, img, content_height(img)))

    tallest = max(h for _, _, h in frames)
    scale = 16 / tallest
    print(f"[{name}] tallest content = {tallest}px  scale = {scale:.6f}")

    finals: list[tuple[str, Image.Image]] = []
    for frame_name, img, ch in frames:
        src_bbox = opaque_bbox(img)
        assert src_bbox is not None, frame_name
        content = img.crop(src_bbox)
        nw = max(1, round(content.width * scale))
        nh = max(1, round(content.height * scale))
        scaled = content.resize((nw, nh), Image.NEAREST)
        c64 = to_c64(
            scaled,
            ban_floor=(frame_name in ban_floor_names),
            extra_allow=extra_allow,
        )
        bbox = opaque_bbox(c64)
        final = c64 if bbox is None else c64.crop(bbox)
        finals.append((frame_name, final))
        print(f"  {frame_name:16} src_h={ch:2d} -> {final.size[0]}x{final.size[1]}")

    max_h = max(im.size[1] for _, im in finals)
    max_w = max(im.size[0] for _, im in finals)
    print(f"[{name}] max output height = {max_h} (target 16)")

    sheet = Image.new("RGBA", (out_cols * max_w, out_rows * max_h), (0, 0, 0, 0))
    for i, (_, im) in enumerate(finals):
        cx = (i % out_cols) * max_w + (max_w - im.size[0]) // 2
        cy = (i // out_cols) * max_h + (max_h - im.size[1]) // 2
        sheet.paste(im, (cx, cy), im)

    sheet_path = out_dir / f"{name}_c64_16_sheet.png"
    sheet.save(sheet_path)
    print(f"[{name}] sheet {sheet.size[0]}x{sheet.size[1]} -> {sheet_path}")

    edit_path = out_dir / f"{name}_c64_sheet_edit.png"
    if refresh_edit or not edit_path.is_file():
        sheet.save(edit_path)
        print(f"[{name}] wrote edit sheet {edit_path.name}")
    elif Image.open(edit_path).size != sheet.size:
        print(
            f"[{name}] note: {edit_path.name} is {Image.open(edit_path).size}, "
            f"new sheet {sheet.size} — copy {sheet_path.name} over it to refresh"
        )
    return sheet_path


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "sets",
        nargs="*",
        choices=("guards", "dogs", "ss", "hans", "all"),
        default=["all"],
        help="which atlases to build (default: all)",
    )
    ap.add_argument(
        "--refresh-edit",
        action="store_true",
        help="overwrite *_c64_sheet_edit.png (default: create only if missing)",
    )
    args = ap.parse_args(argv)
    sets = (
        {"guards", "dogs", "ss", "hans"} if "all" in args.sets else set(args.sets)
    )

    if "guards" in sets:
        process_set(
            name="guards",
            src_sheet=root / "textures" / "guards" / "guards_sheet.png",
            out_dir=root / "textures" / "guards" / "c64_16",
            selected=GUARD_SELECTED,
            out_cols=GUARD_COLS,
            out_rows=GUARD_ROWS,
            src_rows=7,
            ban_floor_names={"guard_dead"},
            refresh_edit=args.refresh_edit,
        )
    if "dogs" in sets:
        process_set(
            name="dogs",
            src_sheet=root / "textures" / "dogs" / "dogs_sheet.png",
            out_dir=root / "textures" / "dogs" / "c64_16",
            selected=DOG_SELECTED,
            out_cols=DOG_COLS,
            out_rows=DOG_ROWS,
            src_rows=5,
            ban_floor_names={"dog_dead"},
            strip_rgb=DOG_MARK_RGB,
            refresh_edit=args.refresh_edit,
        )
    if "ss" in sets:
        process_set(
            name="ss",
            src_sheet=root / "textures" / "ss" / "ss_sheet.png",
            out_dir=root / "textures" / "ss" / "c64_16",
            selected=SS_SELECTED,
            out_cols=SS_COLS,
            out_rows=SS_ROWS,
            src_rows=7,
            ban_floor_names={"ss_dead"},
            refresh_edit=args.refresh_edit,
        )
    if "hans" in sets:
        process_set(
            name="hans",
            src_sheet=root / "textures" / "hans" / "hans_sheet.png",
            out_dir=root / "textures" / "hans" / "c64_16",
            selected=HANS_SELECTED,
            out_cols=HANS_COLS,
            out_rows=HANS_ROWS,
            src_rows=2,
            ban_floor_names={"hans_dead"},
            refresh_edit=args.refresh_edit,
            # Hans armor/accents: cyan ($3), green ($5), yellow ($7)
            extra_allow={3, 5, 7},
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
