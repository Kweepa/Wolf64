#!/usr/bin/env python3
"""
Extract Wolf64 sprites from shareware VSWAP.WL1.

Decodes sparse VSWAP sprite chunks (t_compshape posts) to native 64×64 RGBA.

Default (--guards): all brown-guard frames into textures/guards/:

  guard_s_1.png … guard_s_8.png       standing (8 angles)
  guard_w1_1.png … guard_w4_8.png     walk cycles
  guard_pain_1/2, die_1..3, dead      pain / death
  guard_shoot_1..3                    attack
  guards_sheet.png                    8×7 atlas (64px cells, WL order)

Sheet rows: stand, walk1–4, then pain/die/dead/shoot (9 frames, last cell empty).

Sprite indices follow WL_DEF.H (SPR_DEMO, SPR_DEATHCAM, STAT_0..47, then guards).
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_walls import WOLF_PALETTE, parse_vswap  # noqa: E402

SPR_SIZE = 64

SPR_DEMO = 0
SPR_DEATHCAM = 1
SPR_STAT_0 = 2
SPR_STAT_6 = SPR_STAT_0 + 6
SPR_STAT_14 = SPR_STAT_0 + 14
# Non-Spear: 48 statics after DEATHCAM → first guard stand frame
SPR_GRD_S_1 = SPR_DEATHCAM + 1 + 48  # 50

# WL_DEF.H guard block (49 shapes), names match id Software enums (lowercase).
GUARD_SPRITES: list[tuple[str, int]] = []
_i = SPR_GRD_S_1
for ang in range(1, 9):
    GUARD_SPRITES.append((f"guard_s_{ang}", _i))
    _i += 1
for walk in range(1, 5):
    for ang in range(1, 9):
        GUARD_SPRITES.append((f"guard_w{walk}_{ang}", _i))
        _i += 1
for name in (
    "guard_pain_1",
    "guard_die_1",
    "guard_die_2",
    "guard_die_3",
    "guard_pain_2",
    "guard_dead",
    "guard_shoot_1",
    "guard_shoot_2",
    "guard_shoot_3",
):
    GUARD_SPRITES.append((name, _i))
    _i += 1


def read_sprite_chunk(
    data: bytes, offsets: list[int], lengths: list[int], sprite_start: int, index: int
) -> bytes:
    page = sprite_start + index
    off = offsets[page]
    ln = lengths[page]
    if off == 0 or ln == 0:
        raise ValueError(f"VSWAP sprite {index} (page {page}) is empty")
    chunk = data[off : off + ln]
    if len(chunk) != ln:
        raise ValueError(f"VSWAP sprite {index}: expected {ln} bytes, got {len(chunk)}")
    return chunk


def decode_sprite(chunk: bytes) -> list[list[int | None]]:
    """
    Expand a VSWAP sprite chunk to a 64×64 grid (None = transparent).

    Posts are (endy, newstart, starty) word triplets; pixel at
    chunk[(newstart + row) & 0xFFFF] lands at (x, row) with y=0 at the top.
    """
    left, right = struct.unpack_from("<HH", chunk, 0)
    width = right - left + 1
    grid: list[list[int | None]] = [[None] * SPR_SIZE for _ in range(SPR_SIZE)]

    for col in range(width):
        x = left + col
        if not (0 <= x < SPR_SIZE):
            continue
        linecmds = struct.unpack_from("<H", chunk, 4 + col * 2)[0]
        idx = 0
        while True:
            endy = struct.unpack_from("<H", chunk, linecmds + idx * 2)[0]
            if endy == 0:
                break
            newstart = struct.unpack_from("<H", chunk, linecmds + (idx + 1) * 2)[0]
            starty = struct.unpack_from("<H", chunk, linecmds + (idx + 2) * 2)[0]
            for row in range(starty // 2, endy // 2):
                if not (0 <= row < SPR_SIZE):
                    continue
                pix_i = (newstart + row) & 0xFFFF
                if pix_i < len(chunk):
                    grid[row][x] = chunk[pix_i]
            idx += 3

    return grid


def grid_to_rgba(grid: list[list[int | None]]) -> Image.Image:
    img = Image.new("RGBA", (SPR_SIZE, SPR_SIZE), (0, 0, 0, 0))
    px = img.load()
    for y in range(SPR_SIZE):
        for x in range(SPR_SIZE):
            v = grid[y][x]
            if v is not None:
                px[x, y] = (
                    WOLF_PALETTE[v * 3],
                    WOLF_PALETTE[v * 3 + 1],
                    WOLF_PALETTE[v * 3 + 2],
                    255,
                )
    return img


def load_vswap(shareware: Path) -> tuple[bytes, list[int], list[int], int]:
    vswap_path = shareware / "VSWAP.WL1"
    if not vswap_path.is_file():
        raise FileNotFoundError(vswap_path)
    data, offsets, sprite_start = parse_vswap(vswap_path)
    chunks = struct.unpack_from("<H", data, 0)[0]
    lengths = list(struct.unpack_from(f"<{chunks}H", data, 6 + chunks * 4))
    return data, offsets, lengths, sprite_start


def extract_named(
    shareware: Path,
    out_dir: Path,
    jobs: list[tuple[str, int]],
) -> list[Image.Image]:
    data, offsets, lengths, sprite_start = load_vswap(shareware)
    out_dir.mkdir(parents=True, exist_ok=True)
    images: list[Image.Image] = []
    for name, index in jobs:
        chunk = read_sprite_chunk(data, offsets, lengths, sprite_start, index)
        img = grid_to_rgba(decode_sprite(chunk))
        path = out_dir / f"{name}.png"
        img.save(path)
        images.append(img)
        print(f"{name:16} sprite={index:3d}  -> {path}")
    return images


def write_sheet(
    images: list[Image.Image],
    path: Path,
    *,
    cols: int = 8,
    cell: int = SPR_SIZE,
) -> Path:
    """Pack frames left→right, top→bottom into a transparent atlas."""
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (0, 0, 0, 0))
    for i, img in enumerate(images):
        if img.size != (cell, cell):
            img = img.resize((cell, cell), Image.NEAREST)
        sheet.paste(img, ((i % cols) * cell, (i // cols) * cell), img)
    sheet.save(path)
    print(f"sheet            {cols}x{rows} cells  -> {path}")
    return path


def extract_guards(shareware: Path, out_dir: Path) -> int:
    images = extract_named(shareware, out_dir, GUARD_SPRITES)
    write_sheet(images, out_dir / "guards_sheet.png")
    return len(images)


def extract_props(shareware: Path, out_dir: Path) -> int:
    jobs = [
        ("ceiling_light", SPR_STAT_14),
        ("dog_food", SPR_STAT_6),
    ]
    return len(extract_named(shareware, out_dir, jobs))


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--shareware", type=Path, default=root / "shareware")
    ap.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output directory (default: textures/guards or textures)",
    )
    ap.add_argument(
        "--props",
        action="store_true",
        help="extract ceiling light + dog food instead of guards",
    )
    args = ap.parse_args(argv)
    if args.props:
        out = args.out or (root / "textures")
        n = extract_props(args.shareware, out)
    else:
        out = args.out or (root / "textures" / "guards")
        n = extract_guards(args.shareware, out)
    print(f"Wrote {n} sprites to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
