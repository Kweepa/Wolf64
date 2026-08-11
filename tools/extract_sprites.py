#!/usr/bin/env python3
"""
Extract Wolf64 sprites from shareware VSWAP.WL1.

Decodes sparse VSWAP sprite chunks (t_compshape posts) to native 64×64 RGBA.

Default (--guards): all brown-guard frames into textures/guards/:

  guards_sheet.png                    8×7 atlas (64px cells, WL order)

Sheet rows: stand, walk1–4, then pain/die/dead/shoot (9 frames, last cell empty).
Per-frame PNGs are not written (C64 pipeline uses sheets only).

--items: all 48 static/item sprites (SPR_STAT_0..47) into textures/items/:

  items_sheet.png                     8×6 atlas (64px cells, 1:1, WL order)

--dogs / --ss / --hans: enemy sheets into textures/{dogs,ss,hans}/ (1:1, 8-col).

Per-frame PNGs are not written (sheet only).

Sprite indices follow WL_DEF.H (SPR_DEMO, SPR_DEATHCAM, STAT_0..47, then actors).
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
NUM_STAT_SPRITES = 48
# Non-Spear: 48 statics after DEATHCAM → first guard stand frame
SPR_GRD_S_1 = SPR_DEATHCAM + 1 + NUM_STAT_SPRITES  # 50

# WL_ACT1.C statinfo comments (shareware / non-Spear names).
ITEM_NAMES: list[str] = [
    "puddle",
    "barrel_green",
    "table_chairs",
    "floor_lamp",
    "chandelier",
    "hanged_man",
    "dog_food",
    "pillar_red",
    "tree",
    "skeleton_flat",
    "sink",
    "plant",
    "urn",
    "table_bare",
    "ceiling_light",
    "kitchen",
    "armor",
    "cage",
    "skeleton_cage",
    "skeleton_relax",
    "key_gold",
    "key_silver",
    "bed",
    "water",
    "food",
    "firstaid",
    "ammo_clip",
    "machinegun",
    "chaingun",
    "cross",
    "chalice",
    "bible",
    "crown",
    "oneup",
    "gibs",
    "barrel",
    "well",
    "well_empty",
    "blood",
    "flag",
    "call_apogee",
    "junk_1",
    "junk_2",
    "junk_3",
    "pots",
    "stove",
    "spears",
    "vines",
]

ITEM_SPRITES: list[tuple[str, int]] = [
    (name, SPR_STAT_0 + i) for i, name in enumerate(ITEM_NAMES)
]

# WL_DEF.H actor blocks; names match id Software enums (lowercase).
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

# Dogs: no stand; walk ×4 ×8 dirs, then die/jump (39 shapes) → SPR 99–137.
DOG_SPRITES: list[tuple[str, int]] = []
_i = SPR_GRD_S_1 + len(GUARD_SPRITES)  # 99
for walk in range(1, 5):
    for ang in range(1, 9):
        DOG_SPRITES.append((f"dog_w{walk}_{ang}", _i))
        _i += 1
for name in (
    "dog_die_1",
    "dog_die_2",
    "dog_die_3",
    "dog_dead",
    "dog_jump_1",
    "dog_jump_2",
    "dog_jump_3",
):
    DOG_SPRITES.append((name, _i))
    _i += 1

# SS ("sergeant"): same 49-frame layout as guards → SPR 138–186.
SS_SPRITES: list[tuple[str, int]] = []
_i = SPR_GRD_S_1 + len(GUARD_SPRITES) + len(DOG_SPRITES)  # 138
for ang in range(1, 9):
    SS_SPRITES.append((f"ss_s_{ang}", _i))
    _i += 1
for walk in range(1, 5):
    for ang in range(1, 9):
        SS_SPRITES.append((f"ss_w{walk}_{ang}", _i))
        _i += 1
for name in (
    "ss_pain_1",
    "ss_die_1",
    "ss_die_2",
    "ss_die_3",
    "ss_pain_2",
    "ss_dead",
    "ss_shoot_1",
    "ss_shoot_2",
    "ss_shoot_3",
):
    SS_SPRITES.append((name, _i))
    _i += 1

# Mutants (51) then officers (50, includes DIE_4) then Pac-Man ghosts (8)
# are empty in shareware WL1. Episode 1 boss Hans: 11 frames → SPR 296–306.
SPR_BOSS_W1 = (
    SPR_GRD_S_1
    + len(GUARD_SPRITES)
    + len(DOG_SPRITES)
    + len(SS_SPRITES)
    + 51  # mutants
    + 50  # officers
    + 8  # pac-man ghosts
)  # 296
HANS_SPRITES: list[tuple[str, int]] = []
_i = SPR_BOSS_W1
for walk in range(1, 5):
    HANS_SPRITES.append((f"hans_w{walk}", _i))
    _i += 1
for name in (
    "hans_shoot_1",
    "hans_shoot_2",
    "hans_shoot_3",
    "hans_dead",
    "hans_die_1",
    "hans_die_2",
    "hans_die_3",
):
    HANS_SPRITES.append((name, _i))
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
    *,
    write_individuals: bool = True,
) -> list[Image.Image]:
    data, offsets, lengths, sprite_start = load_vswap(shareware)
    out_dir.mkdir(parents=True, exist_ok=True)
    images: list[Image.Image] = []
    for name, index in jobs:
        chunk = read_sprite_chunk(data, offsets, lengths, sprite_start, index)
        img = grid_to_rgba(decode_sprite(chunk))
        if write_individuals:
            path = out_dir / f"{name}.png"
            img.save(path)
            print(f"{name:16} sprite={index:3d}  -> {path}")
        else:
            print(f"{name:16} sprite={index:3d}")
        images.append(img)
    return images


def write_sheet(
    images: list[Image.Image],
    path: Path,
    *,
    cols: int = 8,
    cell: int = SPR_SIZE,
    scale: int = 1,
) -> Path:
    """Pack frames left→right, top→bottom into a transparent atlas."""
    if scale < 1:
        raise ValueError(f"scale must be >= 1, got {scale}")
    cell_px = cell * scale
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell_px, rows * cell_px), (0, 0, 0, 0))
    for i, img in enumerate(images):
        if img.size != (cell, cell):
            img = img.resize((cell, cell), Image.NEAREST)
        if scale != 1:
            img = img.resize((cell_px, cell_px), Image.NEAREST)
        sheet.paste(img, ((i % cols) * cell_px, (i // cols) * cell_px), img)
    sheet.save(path)
    print(f"sheet            {cols}x{rows} cells @{scale}x  -> {path}")
    return path


def extract_guards(shareware: Path, out_dir: Path, *, scale: int = 1) -> int:
    # Sheet only — process_guard_c64 / pack_enemies consume atlases, not per-frame PNGs.
    images = extract_named(shareware, out_dir, GUARD_SPRITES, write_individuals=False)
    write_sheet(images, out_dir / "guards_sheet.png", scale=scale)
    return len(images)


def extract_items(shareware: Path, out_dir: Path, *, scale: int = 1) -> int:
    """All SPR_STAT_0..47 → 8×6 items_sheet.png only (default 1:1)."""
    images = extract_named(shareware, out_dir, ITEM_SPRITES, write_individuals=False)
    write_sheet(images, out_dir / "items_sheet.png", cols=8, scale=scale)
    return len(images)


def extract_props(shareware: Path, out_dir: Path) -> int:
    jobs = [
        ("ceiling_light", SPR_STAT_14),
        ("dog_food", SPR_STAT_6),
    ]
    return len(extract_named(shareware, out_dir, jobs))


def extract_dogs(shareware: Path, out_dir: Path, *, scale: int = 1) -> int:
    images = extract_named(shareware, out_dir, DOG_SPRITES, write_individuals=False)
    write_sheet(images, out_dir / "dogs_sheet.png", cols=8, scale=scale)
    return len(images)


def extract_ss(shareware: Path, out_dir: Path, *, scale: int = 1) -> int:
    images = extract_named(shareware, out_dir, SS_SPRITES, write_individuals=False)
    write_sheet(images, out_dir / "ss_sheet.png", cols=8, scale=scale)
    return len(images)


def extract_hans(shareware: Path, out_dir: Path, *, scale: int = 1) -> int:
    images = extract_named(shareware, out_dir, HANS_SPRITES, write_individuals=False)
    write_sheet(images, out_dir / "hans_sheet.png", cols=8, scale=scale)
    return len(images)


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--shareware", type=Path, default=root / "shareware")
    ap.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output directory (default: textures/<set>)",
    )
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument(
        "--items",
        action="store_true",
        help="extract all 48 static/item sprites as items_sheet.png only",
    )
    mode.add_argument(
        "--props",
        action="store_true",
        help="extract ceiling light + dog food instead of guards",
    )
    mode.add_argument(
        "--dogs",
        action="store_true",
        help="extract dog frames as dogs_sheet.png (39 sprites, 8×5)",
    )
    mode.add_argument(
        "--ss",
        action="store_true",
        help="extract SS/sergeant frames as ss_sheet.png (49 sprites, 8×7)",
    )
    mode.add_argument(
        "--hans",
        action="store_true",
        help="extract episode 1 boss (Hans) as hans_sheet.png (11 sprites, 8×2)",
    )
    ap.add_argument(
        "--scale",
        type=int,
        default=1,
        help="nearest-neighbor upscale for the atlas only (default: 1 = native 64px)",
    )
    args = ap.parse_args(argv)
    if args.scale < 1:
        ap.error("--scale must be >= 1")
    if args.items:
        out = args.out or (root / "textures" / "items")
        n = extract_items(args.shareware, out, scale=args.scale)
    elif args.props:
        out = args.out or (root / "textures")
        n = extract_props(args.shareware, out)
    elif args.dogs:
        out = args.out or (root / "textures" / "dogs")
        n = extract_dogs(args.shareware, out, scale=args.scale)
    elif args.ss:
        out = args.out or (root / "textures" / "ss")
        n = extract_ss(args.shareware, out, scale=args.scale)
    elif args.hans:
        out = args.out or (root / "textures" / "hans")
        n = extract_hans(args.shareware, out, scale=args.scale)
    else:
        out = args.out or (root / "textures" / "guards")
        n = extract_guards(args.shareware, out, scale=args.scale)
    print(f"Wrote {n} sprites to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
