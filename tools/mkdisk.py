#!/usr/bin/env python3
"""Build wolf64.d64 from game_image.prg (+ boot.prg) via c1541.

Splits the fat ACME image (load @ TABLES) into tab/locode/tex/wpn/paint/sfx/enemy
using symbols from wolf64.lbl, stages maps at MAP ($EF00).
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple

MAP_LOAD = 0xEF00
MAP_SIZE = 4096

# (dos_name, start_sym, end_sym)
SEGMENTS = [
	("tab", "TABLES", "end_tab"),
	("locode", "LOCODE_BASE", "end_locode"),
	("tex", "TEXTURES", "end_tex"),
	("wpn", "PISTOL_SPRITES", "end_wpn"),
	("paint", "PAINTERS", "end_paint"),
	("sfx", "SFX_BASE", "end_sfx"),
	("enemy", "ENEMY_BASE", "end_enemy"),
]

# maps/NN_Wolf1_*.bin → e1mN dos name (boss/secret as e1mb / e1ms)
MAP_FILES = [
	("e1m1", "00_Wolf1_Map1.bin"),
	("e1m2", "01_Wolf1_Map2.bin"),
	("e1m3", "02_Wolf1_Map3.bin"),
	("e1m4", "03_Wolf1_Map4.bin"),
	("e1m5", "04_Wolf1_Map5.bin"),
	("e1m6", "05_Wolf1_Map6.bin"),
	("e1m7", "06_Wolf1_Map7.bin"),
	("e1m8", "07_Wolf1_Map8.bin"),
	("e1mb", "08_Wolf1_Boss.bin"),
	("e1ms", "09_Wolf1_Secret.bin"),
]

LBL_RE = re.compile(r"^al C:([0-9a-fA-F]+)\s+\.(\S+)\s*$")


def find_c1541(explicit: Optional[Path] = None) -> Optional[Path]:
	if explicit is not None:
		return explicit if explicit.is_file() else None
	env = os.environ.get("VICE_BIN")
	if env:
		for name in ("c1541.exe", "c1541"):
			p = Path(env) / name
			if p.is_file():
				return p
	w = shutil.which("c1541")
	return Path(w) if w else None


def parse_lbl(path: Path) -> Dict[str, int]:
	syms: Dict[str, int] = {}
	for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
		m = LBL_RE.match(line.strip())
		if m:
			syms[m.group(2)] = int(m.group(1), 16)
	return syms


def slice_image(body: bytes, load_addr: int, start: int, end: int) -> bytes:
	if start < load_addr:
		raise ValueError(f"slice start ${start:04X} < load ${load_addr:04X}")
	if end < start:
		raise ValueError(f"slice end ${end:04X} < start ${start:04X}")
	off0 = start - load_addr
	off1 = end - load_addr
	if off1 > len(body):
		raise ValueError(
			f"slice ${start:04X}-${end:04X} past image end "
			f"(load ${load_addr:04X}, len={len(body)})"
		)
	return struct.pack("<H", start) + body[off0:off1]


def stage_map(bin_path: Path, out_path: Path) -> None:
	data = bin_path.read_bytes()
	if len(data) != MAP_SIZE:
		print(
			f"warning: {bin_path.name} is {len(data)} bytes (expected {MAP_SIZE})",
			file=sys.stderr,
		)
	out_path.write_bytes(struct.pack("<H", MAP_LOAD) + data)


def main() -> None:
	ap = argparse.ArgumentParser(description="Build wolf64.d64 via c1541")
	ap.add_argument("--out", default="wolf64.d64")
	ap.add_argument("--image", default="game_image.prg", help="fat ACME CBM image")
	ap.add_argument("--boot", default="boot.prg")
	ap.add_argument("--labels", default="wolf64.lbl")
	ap.add_argument("--maps", default="maps")
	ap.add_argument("--all-maps", action="store_true", help="include all Wolf1 maps")
	ap.add_argument("--c1541", type=Path, default=None)
	args = ap.parse_args()

	c1541 = find_c1541(args.c1541)
	if not c1541:
		print(
			"c1541 not found. Install VICE or set VICE_BIN / --c1541.",
			file=sys.stderr,
		)
		sys.exit(1)

	image_path = Path(args.image)
	boot_path = Path(args.boot)
	lbl_path = Path(args.labels)
	for p in (image_path, boot_path, lbl_path):
		if not p.is_file():
			print(f"missing: {p}", file=sys.stderr)
			sys.exit(1)

	syms = parse_lbl(lbl_path)
	for need in (
		"TABLES",
		"end_tab",
		"LOCODE_BASE",
		"end_locode",
		"TEXTURES",
		"end_tex",
		"PISTOL_SPRITES",
		"end_wpn",
		"PAINTERS",
		"end_paint",
		"SFX_BASE",
		"end_sfx",
		"ENEMY_BASE",
		"end_enemy",
	):
		if need not in syms:
			print(f"missing label .{need} in {lbl_path}", file=sys.stderr)
			sys.exit(1)

	raw = image_path.read_bytes()
	load_addr = struct.unpack_from("<H", raw)[0]
	body = raw[2:]
	expected = syms["TABLES"]
	if load_addr != expected:
		print(
			f"image load ${load_addr:04X} != TABLES ${expected:04X}",
			file=sys.stderr,
		)
		sys.exit(1)

	d64 = Path(args.out)
	maps_dir = Path(args.maps)

	with tempfile.TemporaryDirectory(prefix="w64_disk_") as tmp:
		tmp_dir = Path(tmp)
		staged: List[Tuple[str, Path]] = []

		for dos_name, start_sym, end_sym in SEGMENTS:
			start = syms[start_sym]
			end = syms[end_sym]
			out = tmp_dir / dos_name
			out.write_bytes(slice_image(body, load_addr, start, end))
			staged.append((dos_name, out))
			print(f"  {dos_name}: ${start:04X}-${end:04X} ({end - start} bytes)")

		map_list = MAP_FILES if args.all_maps else [MAP_FILES[0]]
		for dos_name, fname in map_list:
			src = maps_dir / fname
			if not src.is_file():
				if dos_name == "e1m1":
					print(f"missing required map: {src}", file=sys.stderr)
					sys.exit(1)
				print(f"  skip map {dos_name}: {src} missing")
				continue
			out = tmp_dir / dos_name
			stage_map(src, out)
			staged.append((dos_name, out))
			print(f"  {dos_name}: ${MAP_LOAD:04X} from {fname}")

		cmd = [
			str(c1541),
			"-format",
			"wolf64,64",
			"d64",
			str(d64),
			"-attach",
			str(d64),
			"-write",
			str(boot_path),
			"wolf64",
		]
		for dos_name, path in staged:
			cmd.extend(["-write", str(path), f"{dos_name},p"])
		subprocess.check_call(cmd)

	print(f"Wrote {d64} via {c1541} ({len(staged)} files + boot)")


if __name__ == "__main__":
	main()
