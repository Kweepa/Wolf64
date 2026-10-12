#!/usr/bin/env python3
"""SID-Wizard 1.5 instrument disk -> editor/instruments.json.

The published collection is Hermit's SID-Wizard 1.5 instrument disk
(CSDb release 126797, SID-Wizard-1.5-instruments.d64, 144 .SWI files).
Each file is a PRG at $04A1: the 16-byte instrument header, waveform /
pulse / filter tables, a size byte, and an 8-character name.

Usage:
  python tools/extract_sw_instruments.py path/to/SID-Wizard-1.5-instruments.d64
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "editor" / "instruments.json"

# Header offsets inside a SID-Wizard instrument image.
PW_PTR = 0x0A
FILT_PTR = 0x0B
HEADER = 0x10


def sector_offset(track: int, sector: int) -> int:
    off = 0
    for t in range(1, track):
        if t <= 17:
            off += 21 * 256
        elif t <= 24:
            off += 19 * 256
        elif t <= 30:
            off += 18 * 256
        else:
            off += 17 * 256
    return off + sector * 256


def read_chain(data: bytes, track: int, sector: int) -> bytes:
    out = bytearray()
    seen: set[tuple[int, int]] = set()
    while track:
        key = (track, sector)
        if key in seen:
            break
        seen.add(key)
        off = sector_offset(track, sector)
        sec = data[off : off + 256]
        nxt, nsec = sec[0], sec[1]
        if nxt == 0:
            out += sec[2 : 2 + nsec]
            break
        out += sec[2:]
        track, sector = nxt, nsec
    return bytes(out)


def directory(data: bytes) -> list[tuple[str, int, int]]:
    files = []
    track, sector = 18, 1
    while track:
        sec = data[sector_offset(track, sector) : sector_offset(track, sector) + 256]
        nxt, nsec = sec[0], sec[1]
        for i in range(8):
            ent = sec[i * 32 : (i + 1) * 32]
            if ent[2] == 0:
                continue
            name = bytes(0x20 if b == 0xA0 else b for b in ent[5:21]).decode("latin1").rstrip()
            files.append((name, ent[3], ent[4]))
        track, sector = nxt, nsec
    return files


def petscii_name(raw: bytes) -> str:
    chars = []
    for b in raw:
        if b == 0:
            break
        chars.append(chr(b) if 32 <= b < 127 else " ")
    return "".join(chars).strip(" .")


def split_swi(prg: bytes) -> tuple[bytes, str]:
    if len(prg) < 2 or prg[0] != 0xA1 or prg[1] != 0x04:
        raise ValueError("not a SID-Wizard instrument PRG ($04A1)")
    body = prg[2:]
    size_at = None
    for i, val in enumerate(body):
        if val == i and i + 9 <= len(body) and all(32 <= c < 127 for c in body[i + 1 : i + 9]):
            size_at = i
    if size_at is None or size_at < HEADER:
        raise ValueError("instrument size byte not found")
    image = body[:size_at]
    pw = image[PW_PTR]
    filt = image[FILT_PTR]
    if not (HEADER < pw <= filt <= len(image)):
        raise ValueError(f"table pointers out of range pw=${pw:02X} filt=${filt:02X}")
    name = petscii_name(body[size_at + 1 : size_at + 9])
    return image, name


def main() -> None:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} INSTRUMENTS.d64", file=sys.stderr)
        sys.exit(1)
    disk = Path(sys.argv[1])
    data = disk.read_bytes()
    if len(data) != 174848:
        raise SystemExit(f"{disk} is not a standard 35-track D64")
    instruments = []
    for filename, track, sector in directory(data):
        if not filename.upper().endswith(".SWI"):
            continue
        image, internal = split_swi(read_chain(data, track, sector))
        ident = filename[:-4]
        instruments.append({
            "id": ident,
            "name": internal or ident,
            "raw": image.hex(),
        })
    instruments.sort(key=lambda item: item["id"])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(instruments, indent=1) + "\n", encoding="utf-8")
    print(f"extract_sw_instruments: {len(instruments)} instruments -> {OUT}")


if __name__ == "__main__":
    main()
