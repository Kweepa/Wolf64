#!/usr/bin/env python3
"""
Extract / rebuild Wolf64 wall textures.

Default: pull MapFormat walls (IDs 0–15) from shareware VSWAP.WL1,
downsample each 64×64 VGA page to 16×16, quantize to Pepto C64 palette.

Authoring: edit textures/walls_preview.png (64×64 = 4×4 of native 16×16
texels), then rebuild the engine blob with --from-preview.

Outputs:
  textures/walls.bin          2 KB engine blob (16 × 128 bytes, 4-bit texels)
  textures/walls_preview.png  64×64 atlas (1:1 texels) for visual QA / editing
  textures/wall_XX_*.png      individual 16×16 previews (nearest-neighbor scaled)
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

from PIL import Image

WALL_SIZE = 64
TEX_SIZE = 16
PAGE_BYTES = WALL_SIZE * WALL_SIZE
NUM_TEXTURES = 16

# Pepto VIC-II palette (VICE pepto-ntsc / common C64 reference)
C64_PALETTE = [
    (0x00, 0x00, 0x00),  # 0 black
    (0xFF, 0xFF, 0xFF),  # 1 white
    (0x67, 0x37, 0x2B),  # 2 red
    (0x70, 0xA3, 0xB1),  # 3 cyan
    (0x6F, 0x3D, 0x86),  # 4 purple
    (0x58, 0x8C, 0x42),  # 5 green
    (0x34, 0x28, 0x79),  # 6 blue
    (0xB7, 0xC6, 0x6E),  # 7 yellow
    (0x6F, 0x4E, 0x25),  # 8 orange
    (0x42, 0x38, 0x00),  # 9 brown
    (0x99, 0x66, 0x59),  # 10 light red
    (0x43, 0x43, 0x43),  # 11 dark grey
    (0x6B, 0x6B, 0x6B),  # 12 medium grey
    (0x9A, 0xD1, 0x83),  # 13 light green
    (0x6B, 0x5E, 0xB5),  # 14 light blue
    (0x95, 0x95, 0x95),  # 15 light grey
]

# Wolf3D VGA palette (Wolf4SDL / uWolf), 6-bit DAC scaled to 0–255
WOLF_PALETTE = [
    0, 0, 0, 0, 0, 170, 0, 170, 0, 0, 170, 170, 170, 0, 0, 170, 0, 170, 170, 85, 0, 170, 170, 170, 85, 85, 85, 85, 85, 255, 85, 255, 85, 85, 255, 255, 255, 85, 85, 255, 85, 255, 255, 255, 85, 255, 255, 255,
    238, 238, 238, 222, 222, 222, 210, 210, 210, 194, 194, 194, 182, 182, 182, 170, 170, 170, 153, 153, 153, 141, 141, 141, 125, 125, 125, 113, 113, 113, 101, 101, 101, 85, 85, 85, 72, 72, 72, 56, 56, 56, 44, 44, 44, 32, 32, 32,
    255, 0, 0, 238, 0, 0, 226, 0, 0, 214, 0, 0, 202, 0, 0, 190, 0, 0, 178, 0, 0, 165, 0, 0, 153, 0, 0, 137, 0, 0, 125, 0, 0, 113, 0, 0, 101, 0, 0, 89, 0, 0, 76, 0, 0, 64, 0, 0,
    255, 218, 218, 255, 186, 186, 255, 157, 157, 255, 125, 125, 255, 93, 93, 255, 64, 64, 255, 32, 32, 255, 0, 0, 255, 170, 93, 255, 153, 64, 255, 137, 32, 255, 121, 0, 230, 109, 0, 206, 97, 0, 182, 85, 0, 157, 76, 0,
    255, 255, 218, 255, 255, 186, 255, 255, 157, 255, 255, 125, 255, 250, 93, 255, 246, 64, 255, 246, 32, 255, 246, 0, 230, 218, 0, 206, 198, 0, 182, 174, 0, 157, 157, 0, 133, 133, 0, 113, 109, 0, 89, 85, 0, 64, 64, 0,
    210, 255, 93, 198, 255, 64, 182, 255, 32, 161, 255, 0, 145, 230, 0, 129, 206, 0, 117, 182, 0, 97, 157, 0, 218, 255, 218, 190, 255, 186, 157, 255, 157, 129, 255, 125, 97, 255, 93, 64, 255, 64, 32, 255, 32, 0, 255, 0,
    0, 255, 0, 0, 238, 0, 0, 226, 0, 0, 214, 0, 4, 202, 0, 4, 190, 0, 4, 178, 0, 4, 165, 0, 4, 153, 0, 4, 137, 0, 4, 125, 0, 4, 113, 0, 4, 101, 0, 4, 89, 0, 4, 76, 0, 4, 64, 0,
    218, 255, 255, 186, 255, 255, 157, 255, 255, 125, 255, 250, 93, 255, 255, 64, 255, 255, 32, 255, 255, 0, 255, 255, 0, 230, 230, 0, 206, 206, 0, 182, 182, 0, 157, 157, 0, 133, 133, 0, 113, 113, 0, 89, 89, 0, 64, 64,
    93, 190, 255, 64, 178, 255, 32, 170, 255, 0, 157, 255, 0, 141, 230, 0, 125, 206, 0, 109, 182, 0, 93, 157, 218, 218, 255, 186, 190, 255, 157, 157, 255, 125, 129, 255, 93, 97, 255, 64, 64, 255, 32, 36, 255, 0, 4, 255,
    0, 0, 255, 0, 0, 238, 0, 0, 226, 0, 0, 214, 0, 0, 202, 0, 0, 190, 0, 0, 178, 0, 0, 165, 0, 0, 153, 0, 0, 137, 0, 0, 125, 0, 0, 113, 0, 0, 101, 0, 0, 89, 0, 0, 76, 0, 0, 64,
    40, 40, 40, 255, 226, 52, 255, 214, 36, 255, 206, 24, 255, 194, 8, 255, 182, 0, 182, 32, 255, 170, 0, 255, 153, 0, 230, 129, 0, 206, 117, 0, 182, 97, 0, 157, 80, 0, 133, 68, 0, 113, 52, 0, 89, 40, 0, 64,
    255, 218, 255, 255, 186, 255, 255, 157, 255, 255, 125, 255, 255, 93, 255, 255, 64, 255, 255, 32, 255, 255, 0, 255, 226, 0, 230, 202, 0, 206, 182, 0, 182, 157, 0, 157, 133, 0, 133, 109, 0, 113, 89, 0, 89, 64, 0, 64,
    255, 234, 222, 255, 226, 210, 255, 218, 198, 255, 214, 190, 255, 206, 178, 255, 198, 165, 255, 190, 157, 255, 186, 145, 255, 178, 129, 255, 165, 113, 255, 157, 97, 242, 149, 93, 234, 141, 89, 222, 137, 85, 210, 129, 80, 202, 125, 76,
    190, 121, 72, 182, 113, 68, 170, 105, 64, 161, 101, 60, 157, 97, 56, 145, 93, 52, 137, 89, 48, 129, 80, 44, 117, 76, 40, 109, 72, 36, 93, 64, 32, 85, 60, 28, 72, 56, 24, 64, 48, 24, 56, 44, 20, 40, 32, 12,
    97, 0, 101, 0, 101, 101, 0, 97, 97, 0, 0, 28, 0, 0, 44, 48, 36, 16, 72, 0, 72, 80, 0, 80, 0, 0, 52, 28, 28, 28, 76, 76, 76, 93, 93, 93, 64, 64, 64, 48, 48, 48, 52, 52, 52, 218, 246, 246,
    186, 234, 234, 157, 222, 222, 117, 202, 202, 72, 194, 194, 32, 182, 182, 32, 178, 178, 0, 165, 165, 0, 153, 153, 0, 141, 141, 0, 133, 133, 0, 125, 125, 0, 121, 121, 0, 117, 117, 0, 113, 113, 0, 109, 109, 153, 0, 137,
]

# MapFormat texture slot -> (name, VSWAP wall page). Light N/S face.
# Door pages: DOORWALL = spriteStart-8 → normal, +4 elevator door, +6 locked.
TEXTURE_SOURCES = [
    (0, "empty", None),  # solid black / unused
    (1, "grey_stone", 0),  # wall tile 1
    (2, "grey_banner", 4),  # wall tile 3
    (3, "blue_stone", 14),  # wall tile 8
    (4, "blue_cell", 8),  # wall tile 5 (cell bars)
    (5, "wood", 22),  # wall tile 12
    (6, "wood_hitler", 20),  # wall tile 11
    (7, "brick", 32),  # wall tile 17
    (8, "brick_wreath", 34),  # wall tile 18
    (9, "purple", 36),  # wall tile 19
    (10, "purple_blood", 48),  # wall tile 25
    (11, "door", 98),  # DOORWALL
    (12, "locked_door", 104),  # DOORWALL+6
    (13, "elevator", 41),  # wall tile 21 dark face (switch panel)
    (14, "pushwall", 0),  # reuse grey (runtime may override)
    (15, "door_jamb", 100),  # DOORWALL+2 side / expansion
]


def parse_vswap(path: Path) -> tuple[bytes, list[int], int]:
    data = path.read_bytes()
    chunks, sprite_start, _sound_start = struct.unpack_from("<HHH", data, 0)
    offsets = list(struct.unpack_from(f"<{chunks}I", data, 6))
    return data, offsets, sprite_start


def read_wall_page(data: bytes, offsets: list[int], page: int) -> bytes:
    off = offsets[page]
    if off == 0:
        raise ValueError(f"VSWAP page {page} is empty")
    chunk = data[off : off + PAGE_BYTES]
    if len(chunk) != PAGE_BYTES:
        raise ValueError(f"VSWAP page {page}: expected {PAGE_BYTES} bytes, got {len(chunk)}")
    return chunk


def page_to_rgb(page: bytes) -> list[tuple[int, int, int]]:
    """Column-major 64×64 indices -> row-major RGB pixels."""
    out: list[tuple[int, int, int]] = [(0, 0, 0)] * (WALL_SIZE * WALL_SIZE)
    for x in range(WALL_SIZE):
        for y in range(WALL_SIZE):
            idx = page[x * WALL_SIZE + y]
            r = WOLF_PALETTE[idx * 3]
            g = WOLF_PALETTE[idx * 3 + 1]
            b = WOLF_PALETTE[idx * 3 + 2]
            out[y * WALL_SIZE + x] = (r, g, b)
    return out


def _saturation(rgb: tuple[int, int, int]) -> int:
    r, g, b = rgb
    return max(r, g, b) - min(r, g, b)


def box_downsample(rgb: list[tuple[int, int, int]], src: int, dst: int) -> list[tuple[int, int, int]]:
    """
    4×4 box average, but keep a vivid feature pixel when a block contains
    strong accent colour (banner cloth, blood, portrait skin, wreath).
    """
    scale = src // dst
    out: list[tuple[int, int, int]] = []
    for y in range(dst):
        for x in range(dst):
            rs = gs = bs = 0
            best = None
            best_score = -1
            for dy in range(scale):
                for dx in range(scale):
                    pix = rgb[(y * scale + dy) * src + (x * scale + dx)]
                    r, g, b = pix
                    rs += r
                    gs += g
                    bs += b
                    # Prefer saturated accents (blood/banner/skin); keep ink lines.
                    sat = _saturation(pix)
                    ink = 255 - max(r, g, b)
                    red_bias = max(0, r - g) + max(0, r - b)
                    score = sat * 2 + red_bias + (ink if ink > 180 else 0)
                    if (sat >= 40 or red_bias >= 60) and score > best_score:
                        best_score = score
                        best = pix
            n = scale * scale
            avg = (rs // n, gs // n, bs // n)
            if best is not None:
                br, bg, bb = best
                if (br - bg >= 40 and br - bb >= 40) or _saturation(best) >= _saturation(avg) + 20:
                    out.append(best)
                    continue
            out.append(avg)
    return out
def nearest_c64(rgb: tuple[int, int, int]) -> int:
    r, g, b = rgb
    best = 0
    best_d = 1 << 30
    for i, (cr, cg, cb) in enumerate(C64_PALETTE):
        dr, dg, db = r - cr, g - cg, b - cb
        # Mild luma emphasis keeps stone / wood bands cleaner on C64 greys.
        d = dr * dr * 2 + dg * dg * 4 + db * db * 3
        if d < best_d:
            best_d = d
            best = i
    return best


def quantize(rgb: list[tuple[int, int, int]]) -> list[int]:
    return [nearest_c64(p) for p in rgb]


def _luma(rgb: tuple[int, int, int]) -> int:
    r, g, b = rgb
    return (r * 2 + g * 5 + b) // 8


def quantize_blue_stone(rgb: list[tuple[int, int, int]]) -> list[int]:
    """
    Blue Wolf walls collapse to flat C64 blue under nearest-color quantize.
    Keep mortar by luma banding: dark→black, mid→blue, bright→light blue.
    """
    lumas = [_luma(p) for p in rgb]
    ordered = sorted(lumas)
    # ~35% darkest = mortar, top ~15% = highlight
    mortar_cut = ordered[max(0, len(ordered) * 35 // 100)]
    hi_cut = ordered[min(len(ordered) - 1, len(ordered) * 85 // 100)]
    out: list[int] = []
    for y in lumas:
        if y <= mortar_cut:
            out.append(0)  # black mortar
        elif y >= hi_cut:
            out.append(14)  # light blue highlight
        else:
            out.append(6)  # blue face
    return out


TEX_STRIDE = 128  # 16 stripes × 8 bytes (checked-in $4800 layout, before map @$5000)


def pack_texture(indices: list[int]) -> bytes:
    """
    Pack 16×16 C64 indices into a 256-byte page-aligned stripe.

    Bytes 0..127: column-major, two vertical texels per byte
    (high nibble = even row, low = odd row). Bytes 128..255: pad.
    """
    out = bytearray(TEX_STRIDE)
    o = 0
    for x in range(TEX_SIZE):
        for y in range(0, TEX_SIZE, 2):
            hi = indices[y * TEX_SIZE + x] & 0x0F
            lo = indices[(y + 1) * TEX_SIZE + x] & 0x0F
            out[o] = (hi << 4) | lo
            o += 1
    return bytes(out)


def indices_to_image(indices: list[int], scale: int = 1) -> Image.Image:
    img = Image.new("P", (TEX_SIZE, TEX_SIZE))
    img.putpalette([c for rgb in C64_PALETTE for c in rgb] + [0] * (768 - 48))
    img.putdata(indices)
    if scale != 1:
        img = img.resize((TEX_SIZE * scale, TEX_SIZE * scale), Image.NEAREST)
    return img.convert("RGB")


PREVIEW_SCALE = 1  # walls_preview is 1:1 (64×64 atlas of 16×16 cells)


def write_outputs(
    out_dir: Path,
    packed_slots: list[tuple[str, list[int]]],
    *,
    labels: list[str] | None = None,
) -> Path:
    """Pack 16 index grids into walls.bin + preview PNGs."""
    out_dir.mkdir(parents=True, exist_ok=True)
    blob = bytearray()
    previews: list[Image.Image] = []

    for slot, (name, indices) in enumerate(packed_slots):
        assert len(indices) == TEX_SIZE * TEX_SIZE
        packed = pack_texture(indices)
        assert len(packed) == TEX_STRIDE
        blob.extend(packed)

        preview = indices_to_image(indices, scale=8)
        preview.save(out_dir / f"wall_{slot:02d}_{name}.png")
        previews.append(indices_to_image(indices, scale=PREVIEW_SCALE))
        colors = sorted(set(indices))
        prefix = labels[slot] if labels else f"{slot:2} {name:14}"
        print(f"{prefix}  c64={colors}")

    assert len(blob) == NUM_TEXTURES * TEX_STRIDE
    bin_path = out_dir / "walls.bin"
    bin_path.write_bytes(blob)

    cell = TEX_SIZE * PREVIEW_SCALE
    atlas = Image.new("RGB", (cell * 4, cell * 4), (0, 0, 0))
    for i, img in enumerate(previews):
        atlas.paste(img, ((i % 4) * cell, (i // 4) * cell))
    atlas_path = out_dir / "walls_preview.png"
    atlas.save(atlas_path)
    print(f"Wrote {bin_path} ({len(blob)} bytes)")
    print(f"Wrote {atlas_path}")
    return bin_path


def cell_rgb_to_indices(cell: Image.Image) -> list[int]:
    """
    Preview cell → 16×16 C64 indices.

    At PREVIEW_SCALE==1 the cell is already native texels. If scaled, samples
    the top-left of each block (matches NEAREST upscale when writing the atlas).
    """
    want = TEX_SIZE * PREVIEW_SCALE
    if cell.size != (want, want):
        cell = cell.resize((want, want), Image.NEAREST)
    rgb = cell.convert("RGB")
    px = rgb.load()
    out: list[int] = []
    for y in range(TEX_SIZE):
        for x in range(TEX_SIZE):
            out.append(nearest_c64(px[x * PREVIEW_SCALE, y * PREVIEW_SCALE]))
    return out


def extract_from_preview(preview_path: Path, out_dir: Path) -> Path:
    """Chop walls_preview.png (4×4 of 16×16) into 16 textures and rebuild walls.bin."""
    if not preview_path.is_file():
        raise FileNotFoundError(preview_path)

    atlas = Image.open(preview_path).convert("RGB")
    cell = TEX_SIZE * PREVIEW_SCALE
    expected = (cell * 4, cell * 4)  # 64×64 at 1:1
    if atlas.size != expected:
        raise ValueError(
            f"{preview_path}: expected {expected[0]}×{expected[1]} "
            f"(4×4 of {cell}×{cell} cells), got {atlas.size[0]}×{atlas.size[1]}"
        )

    names = [name for _, name, _ in TEXTURE_SOURCES]
    slots: list[tuple[str, list[int]]] = []
    for i, name in enumerate(names):
        cx, cy = (i % 4) * cell, (i // 4) * cell
        tile = atlas.crop((cx, cy, cx + cell, cy + cell))
        slots.append((name, cell_rgb_to_indices(tile)))

    return write_outputs(out_dir, slots)


def extract(shareware: Path, out_dir: Path) -> Path:
    vswap_path = shareware / "VSWAP.WL1"
    if not vswap_path.is_file():
        raise FileNotFoundError(vswap_path)

    data, offsets, sprite_start = parse_vswap(vswap_path)
    doorwall = sprite_start - 8
    if doorwall != 98:
        # Still honor computed door base if a different WL1 build appears.
        sources = list(TEXTURE_SOURCES)
        sources[11] = (11, "door", doorwall)
        sources[12] = (12, "locked_door", doorwall + 6)
        sources[15] = (15, "door_jamb", doorwall + 2)
    else:
        sources = TEXTURE_SOURCES

    slots: list[tuple[str, list[int]]] = []
    labels: list[str] = []
    for slot, name, page in sources:
        if page is None:
            indices = [0] * (TEX_SIZE * TEX_SIZE)
        else:
            page_bytes = read_wall_page(data, offsets, page)
            rgb64 = page_to_rgb(page_bytes)
            rgb16 = box_downsample(rgb64, WALL_SIZE, TEX_SIZE)
            if name in ("blue_stone", "blue_cell"):
                indices = quantize_blue_stone(rgb16)
            else:
                indices = quantize(rgb16)
        slots.append((name, indices))
        labels.append(f"{slot:2} {name:14} page={str(page):>4}")

    return write_outputs(out_dir, slots, labels=labels)


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--shareware", type=Path, default=root / "shareware")
    ap.add_argument("--out", type=Path, default=root / "textures")
    ap.add_argument(
        "--from-preview",
        nargs="?",
        const="__default__",
        default=None,
        metavar="PNG",
        help="rebuild walls.bin from walls_preview.png (optional path; "
        "default: <out>/walls_preview.png)",
    )
    args = ap.parse_args(argv)
    if args.from_preview is not None:
        preview = (
            args.out / "walls_preview.png"
            if args.from_preview == "__default__"
            else Path(args.from_preview)
        )
        extract_from_preview(preview, args.out)
    else:
        extract(args.shareware, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
