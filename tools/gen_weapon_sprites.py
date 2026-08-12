#!/usr/bin/env python3
"""
Pack C64-palette weapon PNGs into VIC hi-res sprites + XY/colour tables.

All HUD sprites are VIC XY-expanded (2×). Body + white flash: native
24×21. Opaque black is a body layer (background is PNG transparency).
Flash black is the barrel hole — skipped. Red flash is native (not
½-scale): pistol 1 sprite, machinegun left/right pair, chaingun 3-sprite
triangle. Chaingun stores distinct flash1 and flash2 blobs; runtime swaps.

Outputs:
  src/weapons/wpn_data.asm    sprite blobs (linked at $5000)
  src/weapons/wpn_tables.asm  colours, flush+center XY, counts
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_walls import C64_PALETTE  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
TEX = ROOT / "textures" / "weapons"
OUT_DATA = ROOT / "src" / "weapons" / "wpn_data.asm"
OUT_TABLES = ROOT / "src" / "weapons" / "wpn_tables.asm"

SPR_W, SPR_H = 24, 21
# 2× expand: PNG pixel (px,py) covers 2×2 from sprite origin.
# Visible center 160 → sprite X 184; content left = 184 − cw (cw PNG px ×2).
SCREEN_CX = 184
SCREEN_CY = 150  # sprite Y of visual center (50 + 100)
FLUSH_Y = 249  # bottom of last 2× PNG row
RED_IDX = 10
WHITE_IDX = 1

# Front (low VIC #) → back. Highlights first; black outlines last (behind).
FRONT_ORDER = [1, 15, 14, 3, 12, 10, 8, 11, 9, 2, 4, 5, 6, 7, 13, 0]

WEAPONS = [
    {
        "id": 0,
        "name": "knife",
        "png": "knife.png",
        "flash": None,
        "flash2": None,
        "red_layout": None,
        "align": "tip_center",  # stab: tip X at center, Y still flush bottom
    },
    {
        "id": 1,
        "name": "pistol",
        "png": "pistol.png",
        "flash": "pistol_flash.png",
        "flash2": None,
        "red_layout": "single",
    },
    {
        "id": 2,
        "name": "machinegun",
        "png": "machinegun.png",
        "flash": "machinegun_flash.png",
        "flash2": None,
        "red_layout": "lr",
        "dx": -8,  # one column left
    },
    {
        "id": 3,
        "name": "chaingun",
        "png": "chaingun.png",
        "flash": "chaingun_flash1.png",
        "flash2": "chaingun_flash2.png",
        "red_layout": "triangle",
    },
]


def nearest_c64(rgb: tuple[int, int, int]) -> int:
    r, g, b = rgb
    best, bd = 0, 10**9
    for i, (cr, cg, cb) in enumerate(C64_PALETTE):
        d = (r - cr) ** 2 + (g - cg) ** 2 + (b - cb) ** 2
        if d < bd:
            bd, best = d, i
    return best


def load_indices(path: Path) -> list[list[int | None]]:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    grid: list[list[int | None]] = []
    for y in range(h):
        row: list[int | None] = []
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                row.append(None)
            else:
                row.append(nearest_c64((r, g, b)))
        grid.append(row)
    return grid


def content_bbox(grid: list[list[int | None]]) -> tuple[int, int, int, int]:
    xs: list[int] = []
    ys: list[int] = []
    for y, row in enumerate(grid):
        for x, v in enumerate(row):
            if v is not None:
                xs.append(x)
                ys.append(y)
    if not xs:
        raise ValueError("empty image")
    return min(xs), min(ys), max(xs), max(ys)


def color_pixels(
    grid: list[list[int | None]], idx: int
) -> list[tuple[int, int]]:
    return [
        (x, y)
        for y, row in enumerate(grid)
        for x, v in enumerate(row)
        if v == idx
    ]


def bbox_of(pts: list[tuple[int, int]]) -> tuple[int, int, int, int]:
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def pack_sprite(pts: list[tuple[int, int]], ox: int, oy: int) -> bytes:
    bits = bytearray(64)
    for x, y in pts:
        lx, ly = x - ox, y - oy
        if not (0 <= lx < SPR_W and 0 <= ly < SPR_H):
            continue
        byte_i = ly * 3 + lx // 8
        bits[byte_i] |= 0x80 >> (lx & 7)
    return bytes(bits)


def emit_bytes(data: bytes, per: int = 8) -> str:
    lines = []
    for i in range(0, len(data), per):
        chunk = data[i : i + per]
        lines.append("\t!byte " + ", ".join(f"${b:02x}" for b in chunk))
    return "\n".join(lines)


def red_windows(
    pts: list[tuple[int, int]], layout: str
) -> list[tuple[int, int]]:
    """24×21 window origins covering red pixels."""
    x0, y0, x1, y1 = bbox_of(pts)
    if layout == "single":
        return [(x0, y0)]
    if layout == "lr":
        return [(x0, y0), (x1 - SPR_W + 1, y0)]
    if layout == "triangle":
        top_x = x0 + (x1 - x0 + 1 - SPR_W) // 2
        bot_y = y1 - SPR_H + 1
        return [(top_x, y0), (x0, bot_y), (x1 - SPR_W + 1, bot_y)]
    raise ValueError(f"unknown red layout {layout!r}")


class Layer:
    __slots__ = ("name", "color", "ox", "oy", "data", "expand", "sx", "sy")

    def __init__(
        self,
        name: str,
        color: int,
        ox: int,
        oy: int,
        data: bytes,
        expand: bool = False,
    ):
        self.name = name
        self.color = color
        self.ox = ox
        self.oy = oy
        self.data = data
        self.expand = expand
        self.sx = 0
        self.sy = 0


def pack_color_layers(
    name: str, idx: int, pts: list[tuple[int, int]]
) -> list[Layer]:
    """One 24×21 sprite, or two overlapping 24-wide windows if wider."""
    x0, y0, x1, y1 = bbox_of(pts)
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    if bh > SPR_H:
        raise ValueError(f"{name} colour {idx} bbox {bw}x{bh} exceeds 24x21")
    windows = [x0] if bw <= SPR_W else [x0, x1 - SPR_W + 1]
    layers: list[Layer] = []
    for i, wx in enumerate(windows):
        win = [(x, y) for x, y in pts if wx <= x < wx + SPR_W]
        if not win:
            continue
        _, oy, *_ = bbox_of(win)
        suffix = f"_{i}" if len(windows) > 1 else ""
        layers.append(
            Layer(
                f"{name}_c{idx}{suffix}",
                idx,
                wx,
                oy,
                pack_sprite(win, wx, oy),
            )
        )
    return layers


def body_layers(name: str, grid: list[list[int | None]]) -> list[Layer]:
    colors = sorted(
        {v for row in grid for v in row if v is not None},
        key=lambda c: FRONT_ORDER.index(c) if c in FRONT_ORDER else 99,
    )
    layers: list[Layer] = []
    for idx in colors:
        layers.extend(pack_color_layers(name, idx, color_pixels(grid, idx)))
    return layers


def flash_layers(stem: str, path: Path, red_layout: str) -> list[Layer]:
    grid = load_indices(path)
    wpts = color_pixels(grid, WHITE_IDX)
    if not wpts:
        raise ValueError(f"{path.name}: no white flash")
    wx0, wy0, wx1, wy1 = bbox_of(wpts)
    bw, bh = wx1 - wx0 + 1, wy1 - wy0 + 1
    if bw > SPR_W or bh > SPR_H:
        raise ValueError(f"{path.name} white {bw}x{bh} exceeds 24x21")
    layers = [
        Layer(
            f"{stem}_white",
            WHITE_IDX,
            wx0,
            wy0,
            pack_sprite(wpts, wx0, wy0),
        )
    ]
    rpts = color_pixels(grid, RED_IDX)
    if not rpts:
        raise ValueError(f"{path.name}: no red flash")
    wins = red_windows(rpts, red_layout)
    covered = set()
    for i, (wx, wy) in enumerate(wins):
        win = [
            (x, y)
            for x, y in rpts
            if wx <= x < wx + SPR_W and wy <= y < wy + SPR_H
        ]
        if not win:
            raise ValueError(f"{path.name} red window {i} empty")
        covered.update(win)
        layers.append(
            Layer(
                f"{stem}_red_{i}",
                RED_IDX,
                wx,
                wy,
                pack_sprite(win, wx, wy),
            )
        )
    miss = [p for p in rpts if p not in covered]
    if miss:
        raise ValueError(f"{path.name} red uncovered {len(miss)} px e.g. {miss[:4]}")
    return layers


def screen_xy(
    png_x: int,
    png_y: int,
    cx0: int,
    cy0: int,
    cy1: int,
    cw: int,
    align: str,
) -> tuple[int, int]:
    """Sprite XY for a 2×-expanded layer at PNG origin."""
    if align == "tip_center":
        # Blade tip (content top-left) on horizontal center; Y flush bottom.
        sx = SCREEN_CX + 2 * (png_x - cx0)
        sy = (FLUSH_Y - 1) - 2 * (cy1 - png_y)
    else:
        sx = SCREEN_CX - cw + 2 * (png_x - cx0)
        sy = (FLUSH_Y - 1) - 2 * (cy1 - png_y)
    if not (0 <= sx <= 255 and 0 <= sy <= 255):
        raise ValueError(f"sprite pos out of range ({sx},{sy})")
    return sx, sy


def main() -> int:
    packed: list[dict] = []
    all_layers: list[Layer] = []

    for spec in WEAPONS:
        grid = load_indices(TEX / spec["png"])
        cx0, cy0, cx1, cy1 = content_bbox(grid)
        cw = cx1 - cx0 + 1
        body = body_layers(spec["name"], grid)
        flash: list[Layer] = []
        flash2: list[Layer] = []
        if spec["flash"]:
            flash = flash_layers(
                spec["name"] + "_f1", TEX / spec["flash"], spec["red_layout"]
            )
        if spec.get("flash2"):
            flash2 = flash_layers(
                spec["name"] + "_f2", TEX / spec["flash2"], spec["red_layout"]
            )
            if len(flash2) != len(flash):
                raise SystemExit(
                    f"{spec['name']} flash2 count {len(flash2)} != flash1 {len(flash)}"
                )
        align = spec.get("align", "flush_center")
        dx = spec.get("dx", 0)
        dy = spec.get("dy", 0)
        for layer in body + flash + flash2:
            layer.sx, layer.sy = screen_xy(
                layer.ox, layer.oy, cx0, cy0, cy1, cw, align
            )
            layer.sx += dx
            layer.sy += dy
            if not (0 <= layer.sx <= 255 and 0 <= layer.sy <= 255):
                raise ValueError(
                    f"{layer.name} sprite pos out of range ({layer.sx},{layer.sy})"
                )
        packed.append(
            {
                "spec": spec,
                "body": body,
                "flash": flash,
                "flash2": flash2,
                "bbox": (cx0, cy0, cx1, cy1),
            }
        )
        all_layers.extend(body)
        all_layers.extend(flash)
        all_layers.extend(flash2)
        print(
            f"{spec['name']:12} body={len(body)} flash={len(flash)} "
            f"flash2={len(flash2)} bbox=({cx0},{cy0})-({cx1},{cy1}) "
            f"{cw}x{cy1 - cy0 + 1}"
        )
        for layer in body + flash + flash2:
            print(
                f"  {layer.name:20} col={layer.color:2} png=({layer.ox:2},{layer.oy:2}) "
                f"scr=({layer.sx:3},{layer.sy:3})"
            )

    nspr = len(all_layers)
    nbytes = nspr * 64
    print(f"total {nspr} sprites ({nbytes} bytes, ${nbytes:04X})")
    # $5000–$5880 (ITEM_SPRITES); do not grow into the item reservation.
    if nbytes > 0x880:
        raise SystemExit(f"weapon sprites ${nbytes:04X} exceed $5000–$587F")

    data_lines = [
        "; Auto-generated by tools/gen_weapon_sprites.py — do not edit",
        "!zone wpn_data",
        "",
    ]
    for spec_pack in packed:
        name = spec_pack["spec"]["name"]
        data_lines.append(f"{name}_spr0")
        for layer in spec_pack["body"]:
            data_lines.append(f"{layer.name}")
            data_lines.append(emit_bytes(layer.data))
        for layer in spec_pack["flash"] + spec_pack["flash2"]:
            data_lines.append(f"{layer.name}")
            data_lines.append(emit_bytes(layer.data))
        data_lines.append("")

    OUT_DATA.parent.mkdir(parents=True, exist_ok=True)
    OUT_DATA.write_text("\n".join(data_lines) + "\n", encoding="utf-8", newline="\n")

    def ptr_expr(label: str) -> str:
        return f"({label} - SCREEN) / 64"

    nbody = [len(p["body"]) for p in packed]
    nflash = [len(p["flash"]) for p in packed]
    en_body = [((1 << n) - 1) & 0xFF for n in nbody]
    en_fire = [
        (b | ((((1 << nf) - 1) << nb) & 0xFF)) if nf else b
        for b, nb, nf in zip(en_body, nbody, nflash)
    ]

    def pad(vals: list[int], n: int) -> list[int]:
        return vals + [0] * (n - len(vals))

    cols: list[int] = []
    xs: list[int] = []
    ys: list[int] = []
    fx: list[int] = []
    fy: list[int] = []
    flash_ptr_labels = []
    flash2_ptr_labels = []
    for p in packed:
        cols.extend(pad([ly.color for ly in p["body"]], 8))
        xs.extend(pad([ly.sx for ly in p["body"]], 8))
        ys.extend(pad([ly.sy for ly in p["body"]], 8))
        fx.extend(pad([ly.sx for ly in p["flash"]], 4))
        fy.extend(pad([ly.sy for ly in p["flash"]], 4))
        fx.extend(pad([ly.sx for ly in p["flash2"]], 4))
        fy.extend(pad([ly.sy for ly in p["flash2"]], 4))
        flash_ptr_labels.append(p["flash"][0].name if p["flash"] else None)
        flash2_ptr_labels.append(p["flash2"][0].name if p["flash2"] else None)

    def bcol(vals: list[int]) -> str:
        return "\t!byte " + ", ".join(str(v) for v in vals)

    def ptr_row(labels: list[str | None]) -> str:
        return ", ".join(
            "0" if lab is None else ptr_expr(lab) for lab in labels
        )

    tbl = [
        "; Auto-generated by tools/gen_weapon_sprites.py — do not edit",
        "; Flush+centered sprite XY (knife: tip X at center, Y flush); runtime adds pose delta.",
        "; Chaingun flash B uses distinct flash2 blobs + XY (slots 4..7).",
        "!zone wpn_tables",
        "",
        "KNIFE_SPR_PTR0 = " + ptr_expr("knife_spr0"),
        "PISTOL_SPR_PTR0 = " + ptr_expr("pistol_spr0"),
        "MACHINEGUN_SPR_PTR0 = " + ptr_expr("machinegun_spr0"),
        "CHAINGUN_SPR_PTR0 = " + ptr_expr("chaingun_spr0"),
        "",
        "wpn_nbody",
        bcol(nbody),
        "wpn_nflash",
        bcol(nflash),
        "wpn_en_body",
        bcol(en_body),
        "wpn_en_fire",
        bcol(en_fire),
        "wpn_body_ptr0",
        "\t!byte KNIFE_SPR_PTR0, PISTOL_SPR_PTR0, MACHINEGUN_SPR_PTR0, CHAINGUN_SPR_PTR0",
        "wpn_flash_ptr0",
        "\t!byte " + ptr_row(flash_ptr_labels),
        "wpn_flash_ptr1",
        "\t!byte " + ptr_row(flash2_ptr_labels),
        "",
        "; 8 slots per weapon (body 0..nbody-1)",
        "wpn_spr_col",
        bcol(cols),
        "wpn_spr_x",
        bcol(xs),
        "wpn_spr_y",
        bcol(ys),
        "",
        "; 8 slots per weapon: flash1 (0..3) then flash2 (4..7)",
        "wpn_flash_x",
        bcol(fx),
        "wpn_flash_y",
        bcol(fy),
        "",
    ]
    OUT_TABLES.write_text("\n".join(tbl), encoding="utf-8", newline="\n")
    print(f"wrote {OUT_DATA.relative_to(ROOT)} + {OUT_TABLES.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
