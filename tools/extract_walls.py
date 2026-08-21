#!/usr/bin/env python3
"""
Extract / rebuild Wolf64 wall textures.

Default: pull MapFormat walls (IDs 0–15) from shareware VSWAP.WL1,
downsample each 64×64 VGA page to 16×16, quantize to Pepto C64 palette,
write textures/tex_lo.bin only (does not touch walls_preview.png).

Authoring: edit textures/walls_preview.png (64×64 = 4×4 of native 16×16
texels), then rebuild the engine blob with --from-preview.

Outputs:
  textures/tex_lo.bin   4 KB engine blob: row*256+texx*16+id, one texel/byte.
                        TEX_HI is *not* shipped — the engine builds it at
                        boot by shifting each TEX_LO byte left 4 bits
                        (tex_hi[addr] = tex_lo[addr]<<4), see init_tex_hi.

Optional (--sheet PATH): write a separate 1:1 64×64 atlas (never auto-writes
walls_preview.png). Purple / purple_blood use a blue-shadow bias.

Hand-edit atlas (never overwritten by this tool):
  textures/walls_preview.png  64×64 sheet (1:1 texels)
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
    (0, "locked_gold", 104),  # gold lock plate (author gold tint in walls_preview)
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
    (12, "locked_silver", 104),  # silver lock plate (DOORWALL+6)
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


def box_downsample_purple(
    rgb: list[tuple[int, int, int]], src: int, dst: int, *, accent_blend: float = 0.895
) -> list[tuple[int, int, int]]:
    """
    Like box_downsample, but softens magenta accent lock so crack averages
    pull stone faces toward the blue/dark mortar between blocks (~40/60 purple/blue).
    Pure red blood accents stay full-strength.
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
                keep = (br - bg >= 40 and br - bb >= 40) or _saturation(best) >= _saturation(
                    avg
                ) + 20
                if keep:
                    # Blood splat: keep vivid red. Magenta stone: soft-blend with avg.
                    if br - bg >= 40 and br - bb >= 40 and br > bb + 20:
                        out.append(best)
                    else:
                        t = accent_blend
                        out.append(
                            (
                                int(br * t + avg[0] * (1 - t)),
                                int(bg * t + avg[1] * (1 - t)),
                                int(bb * t + avg[2] * (1 - t)),
                            )
                        )
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


def _luma(rgb: tuple[int, int, int]) -> int:
    r, g, b = rgb
    return (r * 2 + g * 5 + b) // 8


def nearest_c64_purple(rgb: tuple[int, int, int]) -> int:
    """
    Prefer C64 blue (6) for dark mortar/cracks; bias purple walls toward
    roughly 40% purple / 60% blue among those two colours.
    """
    r, g, b = rgb
    luma = _luma(rgb)
    shadow = luma < 46
    best = 0
    best_d = 1 << 30
    for i, (cr, cg, cb) in enumerate(C64_PALETTE):
        dr, dg, db = r - cr, g - cg, b - cb
        d = dr * dr * 2 + dg * dg * 4 + db * db * 3
        if i == 4:  # purple
            d = int(d * (1.5 if shadow else 1.15))
        elif i == 6:  # blue
            d = int(d * (0.55 if shadow else 0.96))
        if d < best_d:
            best_d = d
            best = i
    return best


def quantize(rgb: list[tuple[int, int, int]]) -> list[int]:
    return [nearest_c64(p) for p in rgb]


def quantize_purple_stone(rgb: list[tuple[int, int, int]]) -> list[int]:
    return [nearest_c64_purple(p) for p in rgb]


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


PREVIEW_SCALE = 1  # walls_preview is 1:1 (64×64 atlas of 16×16 cells)


def indices_to_image(indices: list[int], scale: int = 1) -> Image.Image:
    img = Image.new("P", (TEX_SIZE, TEX_SIZE))
    img.putpalette([c for rgb in C64_PALETTE for c in rgb] + [0] * (768 - 48))
    img.putdata(indices)
    if scale != 1:
        img = img.resize((TEX_SIZE * scale, TEX_SIZE * scale), Image.NEAREST)
    return img.convert("RGB")


def write_preview_sheet(packed_slots: list[tuple[str, list[int]]], path: Path) -> Path:
    """Write a 1:1 4×4 atlas (64×64). Never used for walls_preview unless path says so."""
    cell = TEX_SIZE * PREVIEW_SCALE
    atlas = Image.new("RGB", (cell * 4, cell * 4), (0, 0, 0))
    for i, (_name, indices) in enumerate(packed_slots):
        assert len(indices) == TEX_SIZE * TEX_SIZE
        tile = indices_to_image(indices, scale=PREVIEW_SCALE)
        atlas.paste(tile, ((i % 4) * cell, (i // 4) * cell))
    path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(path)
    print(f"Wrote {path} ({atlas.size[0]}x{atlas.size[1]})")
    return path


def pack_tex_lo(packed_slots: list[tuple[str, list[int]]]) -> bytes:
    """
    Build TEX_LO: engine reads it with X = texx*16+id, no AND/shift/SMC needed
    at runtime (see tools/gen_painters.py header for the addressing).

    TEX_LO[row*256 + texx*16 + id] = texel   (hi nibble already 0; texel is 0..15)

    TEX_HI is not shipped: it is texel<<4 of the same data, one nibble-shift
    per byte, generated once at boot into RAM (init_tex_hi) instead of loaded.
    """
    assert len(packed_slots) == NUM_TEXTURES
    tex_lo = bytearray(TEX_SIZE * 256)
    for tid, (_name, indices) in enumerate(packed_slots):
        assert len(indices) == TEX_SIZE * TEX_SIZE
        for row in range(TEX_SIZE):
            for texx in range(TEX_SIZE):
                val = indices[row * TEX_SIZE + texx] & 0x0F
                addr = row * 256 + texx * 16 + tid
                tex_lo[addr] = val
    return bytes(tex_lo)


def write_outputs(
    out_dir: Path,
    packed_slots: list[tuple[str, list[int]]],
    *,
    labels: list[str] | None = None,
    write_bin: bool = True,
) -> Path | None:
    """Build tex_lo.bin (engine format — see pack_tex_lo). TEX_HI is derived
    from it at boot, not shipped. Does not write or overwrite PNGs."""
    out_dir.mkdir(parents=True, exist_ok=True)

    for slot, (name, indices) in enumerate(packed_slots):
        assert len(indices) == TEX_SIZE * TEX_SIZE
        colors = sorted(set(indices))
        prefix = labels[slot] if labels else f"{slot:2} {name:14}"
        print(f"{prefix}  c64={colors}")

    if not write_bin:
        return None

    tex_lo = pack_tex_lo(packed_slots)
    lo_path = out_dir / "tex_lo.bin"
    lo_path.write_bytes(tex_lo)
    print(f"Wrote {lo_path} ({len(tex_lo)} bytes)")
    return lo_path


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


def build_slots_from_vswap(
    shareware: Path,
) -> tuple[list[tuple[str, list[int]]], list[str]]:
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
            if name in ("purple", "purple_blood"):
                rgb16 = box_downsample_purple(rgb64, WALL_SIZE, TEX_SIZE)
                indices = quantize_purple_stone(rgb16)
            else:
                rgb16 = box_downsample(rgb64, WALL_SIZE, TEX_SIZE)
                if name in ("blue_stone", "blue_cell"):
                    indices = quantize_blue_stone(rgb16)
                else:
                    indices = quantize(rgb16)
        slots.append((name, indices))
        labels.append(f"{slot:2} {name:14} page={str(page):>4}")
    return slots, labels


def extract(
    shareware: Path,
    out_dir: Path,
    *,
    write_bin: bool = True,
    sheet_path: Path | None = None,
) -> Path | None:
    preview_default = Path(__file__).resolve().parents[1] / "textures" / "walls_preview.png"
    if preview_default.is_file():
        print(
            f"WARNING: {preview_default} exists and is hand-edited (see its git log) — "
            "this raw-VSWAP extraction ignores it and will NOT match the shipped textures. "
            "Use --from-preview instead unless you are intentionally re-bootstrapping the preview.",
            file=sys.stderr,
        )
    slots, labels = build_slots_from_vswap(shareware)
    if sheet_path is not None:
        write_preview_sheet(slots, sheet_path)
    return write_outputs(out_dir, slots, labels=labels, write_bin=write_bin)


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--shareware", type=Path, default=root / "shareware")
    ap.add_argument("--out", type=Path, default=root / "generated" / "textures")
    ap.add_argument(
        "--from-preview",
        nargs="?",
        const="__default__",
        default=None,
        metavar="PNG",
        help="rebuild walls.bin from walls_preview.png (optional path; "
        "default: <out>/walls_preview.png)",
    )
    ap.add_argument(
        "--sheet",
        type=Path,
        default=None,
        metavar="PNG",
        help="write a 1:1 64×64 atlas to this path (does not touch walls_preview.png)",
    )
    ap.add_argument(
        "--no-bin",
        action="store_true",
        help="skip writing walls.bin (sheet-only / dry extract)",
    )
    args = ap.parse_args(argv)
    if args.from_preview is not None:
        preview = (
            root / "textures" / "walls_preview.png"
            if args.from_preview == "__default__"
            else Path(args.from_preview)
        )
        extract_from_preview(preview, args.out)
    else:
        sheet = args.sheet
        if sheet is not None and not sheet.is_absolute():
            sheet = args.out / sheet
        extract(
            args.shareware,
            args.out,
            write_bin=not args.no_bin,
            sheet_path=sheet,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
