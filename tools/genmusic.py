#!/usr/bin/env python3
"""Menu music: music/*.sid → generated/mus1.prg .. musN.prg (load @ $5000).

Filename order is the jukebox order. Each PSID is relocated with sidreloc
to init $5000 / play $5003, zero page parked at $E0–$F4, and must end by
$8000 (the menu's VIC bank). Every STA $D418
becomes JSR vol_stub, which keeps the filter high nibble and ORs
effects_vol ($08FD). A VBI tune (PSID speed bit clear) is flagged so the
menu forces the ~50 Hz CIA latch after init.

Also writes generated/src/menu_tracks.asm (titles, authors, MUSIC_TRACKS).
"""

from __future__ import annotations

import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MUSIC = ROOT / "music"
OUT_DIR = ROOT / "generated"
ASM_OUT = OUT_DIR / "src" / "menu_tracks.asm"

LOAD = 0x5000
INIT = 0x5000
PLAY = 0x5003
LIMIT = 0x8000
EFFECTS_VOL = 0x08FD
ZP_LO = 0xE0
ZP_HI = 0xF4
MAX_VOL_STORES = 4
SIDRELOC_PAGE = f"{LOAD >> 8:02x}"
SIDRELOC_ZP = "e0-f4"

VOL_STA = bytes((0x8D, 0x18, 0xD4))
# php / pha / and #$f0 / ora effects_vol / sta $d418 / pla / plp / rts
VOL_STUB = bytes((
    0x08,
    0x48,
    0x29, 0xF0,
    0x0D, EFFECTS_VOL & 0xFF, EFFECTS_VOL >> 8,
    0x8D, 0x18, 0xD4,
    0x68,
    0x28,
    0x60,
))


def die(msg: str) -> None:
    print(f"genmusic: {msg}", file=sys.stderr)
    sys.exit(1)


def find_sidreloc() -> Path:
    env = os.environ.get("SIDRELOC")
    if env:
        p = Path(env)
        if p.is_file():
            return p
    for name in ("sidreloc.exe", "sidreloc"):
        w = shutil.which(name)
        if w:
            return Path(w)
    die("sidreloc not found. Set SIDRELOC in setup-env.bat")
    raise AssertionError


def psid_fields(data: bytes) -> tuple[int, int, int, int, str, str]:
    """Return load, init, play, speed_bit0, name, author."""
    if len(data) < 0x7C or data[:4] not in (b"PSID", b"RSID"):
        die("not a PSID/RSID")
    _ver, off, load, init, play = struct.unpack(">HHHHH", data[4:14])
    speed = struct.unpack(">I", data[0x12:0x16])[0]
    name = data[0x16:0x36].split(b"\x00", 1)[0].decode("latin1", "replace")
    author = data[0x36:0x56].split(b"\x00", 1)[0].decode("latin1", "replace")
    if load == 0 and off + 2 <= len(data):
        load = data[off] | (data[off + 1] << 8)
    if init == 0:
        init = load
    return load, init, play, speed & 1, name, author


def parse_payload(data: bytes) -> tuple[int, int, int, bytes]:
    if len(data) < 0x7C or data[:4] not in (b"PSID", b"RSID"):
        die("relocated file is not a PSID")
    _ver, off, load, init, play = struct.unpack(">HHHHH", data[4:14])
    body = data[off:]
    if load == 0:
        if len(body) < 2:
            die("relocated SID is missing its load address")
        load = body[0] | (body[1] << 8)
        body = body[2:]
    if init == 0:
        init = load
    return load, init, play, body


def reloc(src: Path, sidreloc: Path) -> tuple[bytes, list[int]]:
    with tempfile.TemporaryDirectory(prefix="wolf_menu_sid_") as tmp:
        out = Path(tmp) / "reloc.sid"
        cmd = [
            str(sidreloc), "-v", "-p", SIDRELOC_PAGE, "-z", SIDRELOC_ZP,
            str(src), str(out),
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        text = (proc.stdout or "") + (proc.stderr or "")
        ok = "Relocation successful" in text
        if (proc.returncode not in (0, 32) and not ok) or not out.is_file():
            msg = text.strip() or f"exit {proc.returncode}"
            die(f"sidreloc failed on {src.name}: {msg}")
        if not ok:
            msg = text.strip() or f"exit {proc.returncode}"
            die(f"sidreloc failed on {src.name}: {msg}")
        zp = parse_zp(text, src.name)
        payload = out.read_bytes()
    return payload, zp


def parse_zp(text: str, name: str) -> list[int]:
    m = re.search(r"New zero-page addresses:\s*(.*)", text)
    if not m:
        die(f"{name}: sidreloc did not report zero-page addresses")
    addrs: list[int] = []
    for tok in m.group(1).split():
        try:
            v = int(tok, 16)
        except ValueError:
            continue
        if v < ZP_LO or v > ZP_HI:
            die(f"{name}: zero page ${v:02X} is outside ${ZP_LO:02X}-${ZP_HI:02X}")
        addrs.append(v)
    return addrs


def patch_volume(body: bytearray, name: str) -> bytearray:
    sites = []
    start = 0
    while True:
        i = body.find(VOL_STA, start)
        if i < 0:
            break
        sites.append(i)
        start = i + 1
    if not 1 <= len(sites) <= MAX_VOL_STORES:
        die(f"{name}: expected 1..{MAX_VOL_STORES} STA $D418, found {len(sites)}")
    stub = LOAD + len(body)
    jsr = bytes((0x20, stub & 0xFF, stub >> 8))
    for i in sites:
        body[i:i + 3] = jsr
    body += VOL_STUB
    end = LOAD + len(body)
    if end > LIMIT:
        die(f"{name}: image ends ${end:04X}, past ${LIMIT:04X}")
    return body


def scr_text(text: str, fallback: str) -> str:
    out = []
    for ch in text.strip():
        o = ord(ch)
        if ch == '"':
            out.append("'")
        elif 32 <= o <= 126:
            out.append(ch)
        else:
            out.append("?")
    s = "".join(out).strip()
    return s if s else fallback


def asm_scr(label: str, text: str) -> str:
    if not text:
        return f"{label}\t!byte 0\n"
    return f'{label}\t!scr "{text}",0\n'


def emit_asm(tracks: list[dict]) -> None:
    n = len(tracks)
    lines = [
        "; Generated by tools/genmusic.py — do not edit.",
        f"MUSIC_TRACKS = {n}",
        "",
        "; 1 = 50 Hz VBI player (menu forces the CIA latch after init).",
        "music_vbi",
    ]
    lines.append("\t!byte " + ", ".join(str(t["vbi"]) for t in tracks))
    lines.append("")
    for i, t in enumerate(tracks, start=1):
        lines.append(asm_scr(f"str_trk{i}", t["title"]).rstrip())
    lines.append("")
    for i, t in enumerate(tracks, start=1):
        lines.append(asm_scr(f"str_now{i}", f"Now playing: {t['title']}").rstrip())
    lines.append("")
    for i, t in enumerate(tracks, start=1):
        credit = f"Track by {t['author']}" if t["author"] else ""
        lines.append(asm_scr(f"str_auth{i}", credit).rstrip())
    lines.append("")
    lines.append("juke_now_lo")
    lines.append("\t!byte " + ", ".join(f"<str_now{i}" for i in range(1, n + 1)))
    lines.append("juke_now_hi")
    lines.append("\t!byte " + ", ".join(f">str_now{i}" for i in range(1, n + 1)))
    lines.append("juke_auth_lo")
    lines.append("\t!byte " + ", ".join(f"<str_auth{i}" for i in range(1, n + 1)))
    lines.append("juke_auth_hi")
    lines.append("\t!byte " + ", ".join(f">str_auth{i}" for i in range(1, n + 1)))
    lines.append("")
    # Menus before the jukebox are 8-byte rows (menu_id * 8 + item).
    # The jukebox is the last row, so it keeps every track plus Back.
    def pad8(items: list[str]) -> list[str]:
        if len(items) < 8:
            return items + ["0"] * (8 - len(items))
        return items

    items_lo = pad8([f"<str_trk{i}" for i in range(1, n + 1)] + ["<str_back"])
    items_hi = pad8([f">str_trk{i}" for i in range(1, n + 1)] + [">str_back"])
    nxt = pad8(["NM_JUKE"] * n + ["NM_BACK"])
    lines.append("!macro juke_next_row {")
    lines.append("\t!byte " + ", ".join(nxt))
    lines.append("}")
    lines.append("!macro juke_menu_lo {")
    lines.append("\t!byte " + ", ".join(items_lo))
    lines.append("}")
    lines.append("!macro juke_menu_hi {")
    lines.append("\t!byte " + ", ".join(items_hi))
    lines.append("}")
    lines.append("")
    ASM_OUT.parent.mkdir(parents=True, exist_ok=True)
    ASM_OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    sids = sorted(MUSIC.glob("*.sid"), key=lambda p: p.name.lower())
    if not sids:
        die(f"no .sid files in {MUSIC}")
    sidreloc = find_sidreloc()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # Drop a stale higher slot if the folder shrank.
    for stale in OUT_DIR.glob("mus*.prg"):
        m = re.fullmatch(r"mus(\d+)", stale.stem, re.IGNORECASE)
        if m and int(m.group(1)) > len(sids):
            stale.unlink()
    tracks = []
    for n, src in enumerate(sids, start=1):
        _load, _init, _play, cia, name, author = psid_fields(src.read_bytes())
        raw, zp = reloc(src, sidreloc)
        load, init, play, payload = parse_payload(raw)
        if (load, init, play) != (LOAD, INIT, PLAY):
            die(
                f"{src.name}: after sidreloc want "
                f"${LOAD:04X}/${INIT:04X}/${PLAY:04X}, "
                f"got ${load:04X}/${init:04X}/${play:04X}"
            )
        body = patch_volume(bytearray(payload), src.name)
        out = OUT_DIR / f"mus{n}.prg"
        out.write_bytes(bytes((LOAD & 0xFF, LOAD >> 8)) + bytes(body))
        last = LOAD + len(body) - 1
        zp_s = " ".join(f"${z:02X}" for z in zp) if zp else "(none)"
        print(f"genmusic: {out.name} ${LOAD:04X}-${last:04X} zp {zp_s} <- {src.name}")
        tracks.append({
            "title": scr_text(name, src.stem),
            "author": scr_text(author, ""),
            "vbi": 0 if cia else 1,
        })
    emit_asm(tracks)
    print(f"genmusic: {len(tracks)} track(s) -> {ASM_OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
