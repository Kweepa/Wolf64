#!/usr/bin/env python3
"""
Process the 20 purple-outlined frames on guards_sheet.png:

  1. Identify frames from purple (107,94,181) selection boxes
  2. Scale uniformly so the tallest content height → 16px
  3. Remap to Pepto C64 palette minus black/white/cyan/green/yellow/light green;
     pink + greys only in the top 4 rows, except ceiling dark grey is never used
     in the top half of the sprite
  4. Clip transparent edges
  5. Write textures/guards/c64_16/*.png (+ contact sheet)
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_walls import C64_PALETTE  # noqa: E402

# Frames inside the purple boxes on guards_sheet.png (WL order / cell layout).
SELECTED = [
    *[f"guard_s_{i}" for i in range(1, 6)],
    *[f"guard_w1_{i}" for i in range(1, 6)],
    *[f"guard_w3_{i}" for i in range(1, 6)],
    "guard_die_1",
    "guard_pain_2",
    "guard_dead",
    "guard_shoot_2",
    "guard_shoot_3",
]

# Pepto indices excluded from guard remap: black, white, cyan, green, yellow, light green.
C64_EXCLUDE = {0, 1, 3, 5, 7, 13}
CEILING_GREY = 11  # sky $b — never in top half
# Face-only (top 4 rows): pink/light red + medium/light grey (+ dark grey only in bottom half).
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


def to_c64(img: Image.Image) -> Image.Image:
    px = img.load()
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    opx = out.load()
    for y in range(h):
        # Face rows: pink + med/light grey OK; ceiling grey banned (top half).
        # Below: no pink/greys at all.
        allowed = C64_GUARD_FACE if y < FACE_ROWS else C64_GUARD_BODY
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            i = nearest_c64_guard((r, g, b), allowed)
            cr, cg, cb = C64_PALETTE[i]
            opx[x, y] = (cr, cg, cb, 255)
    return out


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    src_dir = root / "textures" / "guards"
    out_dir = src_dir / "c64_16"
    out_dir.mkdir(parents=True, exist_ok=True)

    assert len(SELECTED) == 20, len(SELECTED)

    frames: list[tuple[str, Image.Image, int]] = []
    for name in SELECTED:
        img = Image.open(src_dir / f"{name}.png").convert("RGBA")
        frames.append((name, img, content_height(img)))

    tallest = max(h for _, _, h in frames)
    scale = 16 / tallest
    print(f"tallest content = {tallest}px  scale = {scale:.6f}")

    results: list[tuple[str, tuple[int, int]]] = []
    for name, img, ch in frames:
        # Clip source content first so scale maps tallest → exactly 16,
        # then resize, C64-remap, and clip any residual transparent edge.
        src_bbox = opaque_bbox(img)
        assert src_bbox is not None, name
        content = img.crop(src_bbox)
        nw = max(1, round(content.width * scale))
        nh = max(1, round(content.height * scale))
        scaled = content.resize((nw, nh), Image.NEAREST)
        c64 = to_c64(scaled)
        bbox = opaque_bbox(c64)
        final = c64 if bbox is None else c64.crop(bbox)

        path = out_dir / f"{name}.png"
        final.save(path)
        results.append((name, final.size))
        print(
            f"{name:16} src_h={ch:2d} -> {final.size[0]}x{final.size[1]}  {path.name}"
        )

    max_h = max(s[1] for _, s in results)
    print(f"max output height = {max_h} (target 16)")

    max_w = max(s[0] for _, s in results)
    cols = 5
    rows = (len(results) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * max_w, rows * max_h), (0, 0, 0, 0))
    for i, (name, size) in enumerate(results):
        im = Image.open(out_dir / f"{name}.png")
        cx = (i % cols) * max_w + (max_w - size[0]) // 2
        cy = (i // cols) * max_h + (max_h - size[1]) // 2
        sheet.paste(im, (cx, cy), im)
    sheet_path = out_dir / "guards_c64_16_sheet.png"
    sheet.save(sheet_path)
    print(f"sheet {sheet.size[0]}x{sheet.size[1]} -> {sheet_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
