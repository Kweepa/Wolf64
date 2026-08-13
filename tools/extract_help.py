#!/usr/bin/env python3
"""
Extract Wolf3D help screens from shareware VGAGRAPH.WL1.

Writes textures/help/:
  helpart.txt                 — layout article (chunk T_HELPART)
  h_bj.png … h_bottominfo.png — README_LUMP pics (frame + illustrations)
  help_pics_sheet.png         — atlas of those pics

Chunk IDs match this WL1 (H_* = GFXV_WL1.H; HELPART is extern chunk 150).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_ui import (  # noqa: E402
    STARTPICS,
    extract_pic,
    load_huffman,
    load_pictable,
    read_vgahead,
    write_sheet,
)

# README_LUMP — help window chrome + inline illustrations (GFXV_WL1.H).
HELP_PICS: list[tuple[str, int]] = [
    ("h_bj", 3),
    ("h_castle", 4),
    ("h_keyboard", 5),
    ("h_joy", 6),
    ("h_heal", 7),
    ("h_treasure", 8),
    ("h_gun", 9),
    ("h_key", 10),
    ("h_blaze", 11),
    ("h_weapon1234", 12),
    ("h_wolflogo", 13),
    ("h_visa", 14),
    ("h_mc", 15),
    ("h_idlogo", 16),
    ("h_topwindow", 17),
    ("h_leftwindow", 18),
    ("h_rightwindow", 19),
    ("h_bottominfo", 20),
]

# ARTSEXTERN help article in this compact WL1 (no tile chunks).
T_HELPART = 150


def extract_help(shareware: Path, out_dir: Path) -> int:
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

    out_dir.mkdir(parents=True, exist_ok=True)

    from extract_ui import expand_chunk

    art = expand_chunk(graph, starts, nodes, T_HELPART)
    art_path = out_dir / "helpart.txt"
    # Wolf articles are CR/LF Latin-1; normalize to LF for editing on Windows/Unix.
    text = art.decode("latin-1").replace("\r\n", "\n").replace("\r", "\n")
    if not text.endswith("\n"):
        text += "\n"
    art_path.write_text(text, encoding="utf-8", newline="\n")
    pages = text.count("^P")  # ^PAGE… also counts (^P + AGE…)
    print(f"helpart          chunk={T_HELPART}  {len(art)} bytes  ~{pages} pages  -> {art_path}")

    images = []
    for name, chunk in HELP_PICS:
        img = extract_pic(graph, starts, nodes, pictable, chunk)
        path = out_dir / f"{name}.png"
        img.save(path)
        w, h = img.size
        print(f"{name:16} chunk={chunk:3d}  {w}x{h}  -> {path}")
        images.append(img)

    write_sheet(images, out_dir / "help_pics_sheet.png", 6)
    return 1 + len(HELP_PICS)


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--shareware", type=Path, default=root / "shareware")
    ap.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output directory (default: textures/help)",
    )
    args = ap.parse_args(argv)
    out = args.out or (root / "textures" / "help")
    n = extract_help(args.shareware, out)
    print(f"Wrote {n} files to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
