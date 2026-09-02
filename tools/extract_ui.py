#!/usr/bin/env python3
"""
Extract Wolf3D status-bar UI pics from shareware VGAGRAPH.WL1.

Writes textures/ui/:
  digit_0.png .. digit_9.png
  key_none.png, key_gold.png, key_silver.png
  face1a.png .. face7c.png, face8a.png, face_gotgatling.png, face_mutant.png
  ui_digits_sheet.png   (10×1)
  ui_keys_sheet.png     (3×1)
  ui_faces_sheet.png    (8×3)

--faces-sheet PATH writes only the 24 HUD BJ faces as a 3×8 atlas
(look a/b/c × HP 1–7 + dead/gatling/mutant).

Chunk IDs are shareware VGAGRAPH.WL1 (GFXV_WL1.H + 8).
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_walls import WOLF_PALETTE  # noqa: E402

# Chunk IDs for shareware VGAGRAPH.WL1 (STATUSBAR=98 = 320×40).
# GFXV_WL1.H enums are 8 lower (NOKEY=99 → 107); same +8 as FACE1A 113→121.
STRUCTPIC = 0
STARTPICS = 3
STATUSBARPIC = 98
NOKEYPIC = 107
GOLDKEYPIC = 108
SILVERKEYPIC = 109
N_BLANKPIC = 110
N_0PIC = 111
N_9PIC = 120
FACE1APIC = 121
FACE8APIC = 142
GOTGATLINGPIC = 143
MUTANTBJPIC = 144

UI_DIGITS = [(f"digit_{d}", N_0PIC + d) for d in range(10)]
UI_KEYS = [
    ("key_none", NOKEYPIC),
    ("key_gold", GOLDKEYPIC),
    ("key_silver", SILVERKEYPIC),
]
UI_FACES: list[tuple[str, int]] = []
_chunk = FACE1APIC
for tier in range(1, 8):
    for letter in "abc":
        UI_FACES.append((f"face{tier}{letter}", _chunk))
        _chunk += 1
UI_FACES.append(("face8a", FACE8APIC))
UI_FACES.append(("face_gotgatling", GOTGATLINGPIC))
UI_FACES.append(("face_mutant", MUTANTBJPIC))
assert _chunk == FACE8APIC  # face1a..face7c land on face8a


def read_vgahead(path: Path) -> list[int]:
    data = path.read_bytes()
    if len(data) % 3:
        raise ValueError(f"{path.name}: length {len(data)} not divisible by 3")
    offs: list[int] = []
    for i in range(0, len(data), 3):
        o = data[i] | (data[i + 1] << 8) | (data[i + 2] << 16)
        if o == 0xFFFFFF:
            offs.append(-1)
        else:
            offs.append(o)
    return offs


def load_huffman(path: Path) -> list[tuple[int, int]]:
    """255 nodes × (bit0, bit1) as uint16; values <256 are leaves."""
    raw = path.read_bytes()
    if len(raw) < 1020:
        raise ValueError(f"{path.name}: expected ≥1020 bytes, got {len(raw)}")
    nodes = [struct.unpack_from("<HH", raw, i * 4) for i in range(255)]
    return nodes


def huff_expand(source: bytes, length: int, nodes: list[tuple[int, int]]) -> bytes:
    """CAL_HuffExpand — head node is always 254; bit0/bit1 < 256 → output byte."""
    out = bytearray(length)
    head = 254
    node = head
    si = 0
    di = 0
    if not source:
        raise ValueError("empty Huffman source")
    ch = source[si]
    si += 1
    mask = 1
    while di < length:
        bit1 = (ch & mask) != 0
        mask <<= 1
        if mask == 0x100:
            if si >= len(source):
                raise ValueError("Huffman underrun")
            ch = source[si]
            si += 1
            mask = 1
        code = nodes[node][1 if bit1 else 0]
        if code < 256:
            out[di] = code
            di += 1
            node = head
        else:
            node = code - 256
            if not (0 <= node < 255):
                raise ValueError(f"bad Huffman node {code}")
    return bytes(out)


def chunk_slice(graph: bytes, starts: list[int], chunk: int) -> bytes:
    pos = starts[chunk]
    if pos < 0:
        raise ValueError(f"sparse / missing chunk {chunk}")
    # next non-sparse offset (or EOF)
    end = len(graph)
    for nxt in starts[chunk + 1 :]:
        if nxt >= 0:
            end = nxt
            break
    return graph[pos:end]


def expand_chunk(
    graph: bytes, starts: list[int], nodes: list[tuple[int, int]], chunk: int
) -> bytes:
    """
    CAL_ExpandGrChunk for non-tile chunks: first dword = expanded size,
    then Huffman payload (expand that many bytes).
    """
    raw = chunk_slice(graph, starts, chunk)
    if len(raw) < 4:
        raise ValueError(f"chunk {chunk}: too short")
    expanded = struct.unpack_from("<I", raw, 0)[0]
    # STRUCTPIC size is known from pictable; still uses explicit dword.
    return huff_expand(raw[4:], expanded, nodes)


def deplane_vga(planar: bytes, width: int, height: int) -> bytes:
    """VL_DePlaneVGA: planar Mode-X → linear 8-bit indices."""
    if width & 3:
        raise ValueError(f"width {width} not divisible by 4")
    size = width * height
    if len(planar) < size:
        raise ValueError(f"planar data {len(planar)} < {size}")
    linear = bytearray(size)
    pwidth = width >> 2
    src = 0
    for plane in range(4):
        for y in range(height):
            row = y * width
            for x in range(pwidth):
                linear[row + (x << 2) + plane] = planar[src]
                src += 1
    return bytes(linear)


def indices_to_rgba(indices: bytes, width: int, height: int) -> Image.Image:
    img = Image.new("RGBA", (width, height))
    px = img.load()
    i = 0
    for y in range(height):
        for x in range(width):
            v = indices[i]
            i += 1
            px[x, y] = (
                WOLF_PALETTE[v * 3],
                WOLF_PALETTE[v * 3 + 1],
                WOLF_PALETTE[v * 3 + 2],
                255,
            )
    return img


def load_pictable(
    graph: bytes, starts: list[int], nodes: list[tuple[int, int]]
) -> list[tuple[int, int]]:
    data = expand_chunk(graph, starts, nodes, STRUCTPIC)
    if len(data) % 4:
        raise ValueError(f"STRUCTPIC size {len(data)} not multiple of 4")
    return [struct.unpack_from("<HH", data, i) for i in range(0, len(data), 4)]


def extract_pic(
    graph: bytes,
    starts: list[int],
    nodes: list[tuple[int, int]],
    pictable: list[tuple[int, int]],
    chunk: int,
) -> Image.Image:
    if chunk < STARTPICS:
        raise ValueError(f"chunk {chunk} is before STARTPICS")
    pi = chunk - STARTPICS
    if pi >= len(pictable):
        raise ValueError(f"chunk {chunk}: pictable index {pi} out of range")
    width, height = pictable[pi]
    if width == 0 or height == 0:
        raise ValueError(f"chunk {chunk}: empty pictable entry")
    planar = expand_chunk(graph, starts, nodes, chunk)
    need = width * height
    if len(planar) < need:
        raise ValueError(
            f"chunk {chunk}: expanded {len(planar)} < {width}×{height}={need}"
        )
    linear = deplane_vga(planar[:need], width, height)
    return indices_to_rgba(linear, width, height)


def write_sheet(images: list[Image.Image], path: Path, cols: int) -> None:
    if not images:
        return
    cw = max(im.size[0] for im in images)
    ch = max(im.size[1] for im in images)
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cw, rows * ch), (0, 0, 0, 0))
    for i, im in enumerate(images):
        x = (i % cols) * cw + (cw - im.size[0]) // 2
        y = (i // cols) * ch + (ch - im.size[1]) // 2
        sheet.paste(im, (x, y), im)
    sheet.save(path)
    print(f"sheet            {cols}x{rows}  -> {path}")


def load_vgagraph(
    shareware: Path,
) -> tuple[bytes, list[int], list[tuple[int, int]], list[tuple[int, int]]]:
    head = shareware / "VGAHEAD.WL1"
    dic = shareware / "VGADICT.WL1"
    graph_path = shareware / "VGAGRAPH.WL1"
    for p in (head, dic, graph_path):
        if not p.is_file():
            raise FileNotFoundError(p)

    starts = read_vgahead(head)
    nodes = load_huffman(dic)
    graph = graph_path.read_bytes()
    pictable = load_pictable(graph, starts, nodes)
    print(f"pictable         {len(pictable)} entries (STARTPICS={STARTPICS})")
    return graph, starts, nodes, pictable


def extract_faces_sheet(shareware: Path, sheet_path: Path) -> int:
    graph, starts, nodes, pictable = load_vgagraph(shareware)
    images: list[Image.Image] = []
    for name, chunk in UI_FACES:
        img = extract_pic(graph, starts, nodes, pictable, chunk)
        w, h = img.size
        print(f"{name:16} chunk={chunk:3d}  {w}x{h}")
        images.append(img)
    sheet_path.parent.mkdir(parents=True, exist_ok=True)
    write_sheet(images, sheet_path, 3)
    return len(images)


def extract_ui(shareware: Path, out_dir: Path) -> int:
    graph, starts, nodes, pictable = load_vgagraph(shareware)

    out_dir.mkdir(parents=True, exist_ok=True)
    jobs = UI_DIGITS + UI_KEYS + UI_FACES
    images: dict[str, Image.Image] = {}
    for name, chunk in jobs:
        img = extract_pic(graph, starts, nodes, pictable, chunk)
        path = out_dir / f"{name}.png"
        img.save(path)
        w, h = img.size
        print(f"{name:16} chunk={chunk:3d}  {w}x{h}  -> {path}")
        images[name] = img

    write_sheet([images[n] for n, _ in UI_DIGITS], out_dir / "ui_digits_sheet.png", 10)
    write_sheet([images[n] for n, _ in UI_KEYS], out_dir / "ui_keys_sheet.png", 3)
    write_sheet([images[n] for n, _ in UI_FACES], out_dir / "ui_faces_sheet.png", 8)
    return len(jobs)


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--shareware", type=Path, default=root / "shareware")
    ap.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output directory (default: textures/ui)",
    )
    ap.add_argument(
        "--faces-sheet",
        type=Path,
        default=None,
        help="write only the 24 HUD BJ faces as a 3×8 atlas (skip digits/keys)",
    )
    args = ap.parse_args(argv)
    if args.faces_sheet is not None:
        n = extract_faces_sheet(args.shareware, args.faces_sheet)
        print(f"Wrote {n} faces to {args.faces_sheet}")
        return 0
    out = args.out or (root / "textures" / "ui")
    n = extract_ui(args.shareware, out)
    print(f"Wrote {n} pics to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
