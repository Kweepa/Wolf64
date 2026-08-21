#!/usr/bin/env python3
"""
Build C64 item atlas from boxed sprites on items_sheet_selected.png.

  1. Detect purple / white selection rectangles (stacked boxes split at shared edges)
  2. Crop interiors from items_sheet.png
  3. Scale uniformly so the tallest content height → 16px
  4. Remap to Pepto C64 palette (no floor grey $c; those pixels → light blue $e)
  5. Write textures/items/c64/items_c64_sheet.png (+ named PNGs)
     — 5×4 boxed items, then cross/chalice/bible/crown/oneup on row 5

Hand-drawn marks use C64 light blue (same as dogs_sheet) or white.
Never overwrites items_c64_sheet_edit.png (hand edits; pack_items reads that).
"""

from __future__ import annotations

import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_sprites import ITEM_NAMES  # noqa: E402
from extract_walls import C64_PALETTE, nearest_c64  # noqa: E402
from process_enemy_c64 import strip_mark_color  # noqa: E402
from process_guard_c64 import FLOOR_GREY, opaque_bbox  # noqa: E402

SRC_COLS = 8
SRC_CELL = 64
OUT_COLS = 5
OUT_ROWS = 5  # 5×5 atlas (row 5 = treasures + extra life)
TARGET_H = 16
TREASURE_NAMES = ("cross", "chalice", "bible", "crown", "oneup")

# Same annotation colour as dogs_sheet.png (Pepto light blue).
MARK_RGB = (107, 94, 181)
WHITE_RGB = (255, 255, 255)
STROKE = 2
LIGHT_BLUE = 14  # substitute for floor grey (not cyan $3)


def collect_mark_pixels(
    selected: Image.Image, original: Image.Image
) -> list[tuple[int, int]]:
    """Pixels added as selection marks (purple, or white that is not in source)."""
    sp = selected.load()
    op = original.load()
    w, h = selected.size
    marks: list[tuple[int, int]] = []
    for y in range(h):
        for x in range(w):
            sr, sg, sb, sa = sp[x, y]
            if sa < 128:
                continue
            or_, og, ob, oa = op[x, y]
            if (sr, sg, sb, sa) == (or_, og, ob, oa):
                continue
            if (sr, sg, sb) in (MARK_RGB, WHITE_RGB):
                marks.append((x, y))
    return marks


def connected_components(
    pts: list[tuple[int, int]],
) -> list[list[tuple[int, int]]]:
    markset = set(pts)
    visited: set[tuple[int, int]] = set()
    comps: list[list[tuple[int, int]]] = []
    for p in pts:
        if p in visited:
            continue
        stack = [p]
        visited.add(p)
        comp: list[tuple[int, int]] = []
        while stack:
            x, y = stack.pop()
            comp.append((x, y))
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (x + dx, y + dy)
                if q in markset and q not in visited:
                    visited.add(q)
                    stack.append(q)
        comps.append(comp)
    return comps


def rects_from_component(pts: list[tuple[int, int]]) -> list[tuple[int, int, int, int]]:
    """
    Pair horizontal mark-bars into axis-aligned rectangles.

    A single box has top+bottom bars (2 clusters → 1 rect). Stacked boxes that
    share an edge have 3+ clusters and split into one rect per gap.
    """
    by_y: dict[int, list[int]] = defaultdict(list)
    for x, y in pts:
        by_y[y].append(x)
    xs_all = [x for x, _ in pts]
    x_span = max(xs_all) - min(xs_all) + 1
    min_bar = max(8, x_span // 2)

    bar_ys = [y for y, xs in sorted(by_y.items()) if len(xs) >= min_bar]
    if not bar_ys:
        xs = [x for x, _ in pts]
        ys = [y for _, y in pts]
        return [(min(xs), min(ys), max(xs) + 1, max(ys) + 1)]

    clusters: list[tuple[int, int]] = []
    start = prev = bar_ys[0]
    for y in bar_ys[1:]:
        if y <= prev + 2:
            prev = y
        else:
            clusters.append((start, prev))
            start = prev = y
    clusters.append((start, prev))

    if len(clusters) < 2:
        xs = [x for x, _ in pts]
        ys = [y for _, y in pts]
        return [(min(xs), min(ys), max(xs) + 1, max(ys) + 1)]

    rects: list[tuple[int, int, int, int]] = []
    for i in range(len(clusters) - 1):
        y0 = clusters[i][0]
        y1 = clusters[i + 1][1] + 1
        xs = [x for x, y in pts if y0 <= y < y1]
        if len(xs) < 8:
            continue
        rects.append((min(xs), y0, max(xs) + 1, y1))
    return rects


def inset_rect(
    rect: tuple[int, int, int, int], pad: int, bounds: tuple[int, int]
) -> tuple[int, int, int, int]:
    x0, y0, x1, y1 = rect
    w, h = bounds
    x0 = min(max(0, x0 + pad), w - 1)
    y0 = min(max(0, y0 + pad), h - 1)
    x1 = min(max(x0 + 1, x1 - pad), w)
    y1 = min(max(y0 + 1, y1 - pad), h)
    return x0, y0, x1, y1


def detect_boxes(
    selected: Image.Image, original: Image.Image
) -> list[tuple[str, tuple[int, int, int, int]]]:
    """Return (item_name, crop_rect) in sheet order."""
    marks = collect_mark_pixels(selected, original)
    if not marks:
        raise ValueError("no selection marks on items_sheet_selected.png")

    found: list[tuple[int, int, str, tuple[int, int, int, int]]] = []
    seen: set[str] = set()
    for comp in connected_components(marks):
        for rect in rects_from_component(comp):
            x0, y0, x1, y1 = inset_rect(rect, STROKE, selected.size)
            if x1 - x0 < 4 or y1 - y0 < 4:
                continue
            cx = (x0 + x1) // 2
            cy = (y0 + y1) // 2
            col, row = cx // SRC_CELL, cy // SRC_CELL
            idx = row * SRC_COLS + col
            if not (0 <= idx < len(ITEM_NAMES)):
                continue
            name = ITEM_NAMES[idx]
            if name in seen:
                continue
            seen.add(name)
            found.append((row, col, name, (x0, y0, x1, y1)))

    found.sort(key=lambda t: (t[0], t[1]))
    return [(name, rect) for _, _, name, rect in found]


def to_c64(img: Image.Image) -> Image.Image:
    px = img.load()
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    opx = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            i = nearest_c64((r, g, b))
            if i == FLOOR_GREY:
                i = LIGHT_BLUE
            cr, cg, cb = C64_PALETTE[i]
            opx[x, y] = (cr, cg, cb, 255)
    return out


def source_cell_rect(name: str) -> tuple[int, int, int, int]:
    idx = ITEM_NAMES.index(name)
    col, row = idx % SRC_COLS, idx // SRC_COLS
    x0, y0 = col * SRC_CELL, row * SRC_CELL
    return x0, y0, x0 + SRC_CELL, y0 + SRC_CELL


def crop_item(src: Image.Image, rect: tuple[int, int, int, int]) -> Image.Image:
    crop = src.crop(rect).convert("RGBA")
    crop = strip_mark_color(crop, MARK_RGB)
    bbox = opaque_bbox(crop)
    return crop if bbox is None else crop.crop(bbox)


def process_item(content: Image.Image, scale: float) -> Image.Image:
    nw = max(1, round(content.width * scale))
    nh = max(1, round(content.height * scale))
    scaled = content.resize((nw, nh), Image.NEAREST)
    c64 = to_c64(scaled)
    bbox = opaque_bbox(c64)
    return c64 if bbox is None else c64.crop(bbox)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    src_path = root / "textures" / "items" / "items_sheet.png"
    sel_path = root / "textures" / "items" / "items_sheet_selected.png"
    out_dir = root / "textures" / "items" / "c64"  # hand-edit target (tracked)
    gen_dir = root / "generated" / "textures" / "items" / "c64"  # plain dumps
    out_dir.mkdir(parents=True, exist_ok=True)
    gen_dir.mkdir(parents=True, exist_ok=True)

    if not src_path.is_file():
        raise FileNotFoundError(src_path)
    if not sel_path.is_file():
        raise FileNotFoundError(sel_path)

    src = Image.open(src_path).convert("RGBA")
    sel = Image.open(sel_path).convert("RGBA")
    if src.size != sel.size:
        raise ValueError(f"sheet size mismatch: {src.size} vs {sel.size}")

    boxes = detect_boxes(sel, src)
    print(f"boxed items: {len(boxes)}")
    if len(boxes) > OUT_COLS * 4:
        raise ValueError(f"{len(boxes)} items > {OUT_COLS}x{OUT_ROWS} sheet")

    contents: list[tuple[str, Image.Image, int]] = []
    for name, rect in boxes:
        content = crop_item(src, rect)
        ch = content.size[1]
        contents.append((name, content, ch))

    tallest = max(ch for _, _, ch in contents)
    scale = TARGET_H / tallest
    print(f"tallest content = {tallest}px  scale = {scale:.6f}")

    finals: list[tuple[str, Image.Image]] = []
    for name, content, ch in contents:
        im = process_item(content, scale)
        finals.append((name, im))
        path = gen_dir / f"{name}.png"
        im.save(path)
        print(f"  {name:16} src_h={ch:2d} -> {im.size[0]}x{im.size[1]}  {path.name}")

    boxed_names = {name for name, _ in boxes}
    for name in TREASURE_NAMES:
        if name in boxed_names:
            continue
        content = crop_item(src, source_cell_rect(name))
        im = process_item(content, scale)
        finals.append((name, im))
        path = gen_dir / f"{name}.png"
        im.save(path)
        print(f"  {name:16} src_h={content.size[1]:2d} -> {im.size[0]}x{im.size[1]}  {path.name}  (row 5)")

    max_w = max(im.size[0] for _, im in finals)
    max_h = max(im.size[1] for _, im in finals)
    rows = (len(finals) + OUT_COLS - 1) // OUT_COLS
    # Floor-align (bottom of cell). Ceiling props (chandelier, ceiling_light,
    # hanged_man, skeleton_cage, …) get a top-align special case later.
    sheet = Image.new("RGBA", (OUT_COLS * max_w, rows * max_h), (0, 0, 0, 0))
    for i, (_, im) in enumerate(finals):
        cx = (i % OUT_COLS) * max_w + (max_w - im.size[0]) // 2
        cy = (i // OUT_COLS) * max_h + (max_h - im.size[1])
        sheet.paste(im, (cx, cy), im)

    sheet_path = gen_dir / "items_c64_sheet.png"
    sheet.save(sheet_path)
    print(f"sheet {sheet.size[0]}x{sheet.size[1]} ({OUT_COLS}x{rows} of {max_w}x{max_h}) -> {sheet_path}")

    edit_path = out_dir / "items_c64_sheet_edit.png"
    if not edit_path.is_file():
        sheet.save(edit_path)
        print(f"wrote edit sheet {edit_path.name}")
    else:
        print(f"left existing {edit_path.name} untouched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
