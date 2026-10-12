#!/usr/bin/env python3
"""Host checks for the music editor: MIDI parse, SID export, genmusic reloc."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EDITOR = ROOT / "editor"
MUSIC = ROOT / "music"
sys.path.insert(0, str(ROOT / "tools"))

EXPECTED = {
    "GETTHEM.mid": {1: 28, 2: 333, 4: 54, 5: 180, 6: 180, 7: 180, 9: 636},
    "NAZI_NOR.mid": {1: 94, 2: 67, 3: 67, 4: 67, 9: 335},
    "POW.mid": {0: 160, 1: 32, 2: 8, 3: 32, 4: 28, 5: 96, 6: 192, 7: 31},
    "SEARCHN.mid": {2: 50, 3: 50, 4: 50, 5: 64, 6: 44, 7: 384, 9: 378},
    "SUSPENSE.mid": {2: 13, 3: 90, 4: 11, 5: 288, 6: 42, 9: 363},
}


def sidreloc_env() -> None:
    if os.environ.get("SIDRELOC"):
        return
    bat = ROOT / "setup-env.bat"
    if not bat.is_file():
        return
    for line in bat.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.lower().startswith("set sidreloc="):
            os.environ["SIDRELOC"] = line.split("=", 1)[1]
            return


def node_eval(script: str, env: dict | None = None) -> str:
    node = shutil.which("node") or shutil.which("node.exe")
    if not node:
        raise SystemExit("node is required to test the editor scripts")
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as tmp:
        tmp.write(script)
        path = tmp.name
    run_env = os.environ.copy()
    if env:
        run_env.update(env)
    try:
        proc = subprocess.run([node, path], capture_output=True, text=True, cwd=ROOT, env=run_env)
    finally:
        Path(path).unlink(missing_ok=True)
    if proc.returncode != 0:
        raise SystemExit(proc.stderr or proc.stdout)
    return proc.stdout


def load_js() -> str:
    parts = []
    for name in ("midi.js", "sidexport.js", "cpu6502.js", "sidchip.js", "sidmachine.js"):
        parts.append((EDITOR / "js" / name).read_text(encoding="utf-8"))
    instruments = (EDITOR / "instruments.json").read_text(encoding="utf-8")
    player = (EDITOR / "player.bin").read_bytes()
    labels = {}
    for line in (EDITOR / "player.lbl").read_text(encoding="latin1").splitlines():
        bits = line.split()
        if len(bits) >= 3 and bits[1] == "=" and bits[2].startswith("$"):
            labels[bits[0]] = int(bits[2][1:], 16)
    needed = [
        "hdr_vptr_lo", "hdr_vptr_hi", "hdr_vend_lo", "hdr_vend_hi",
        "hdr_iptr_lo", "hdr_iptr_hi", "hdr_iend_lo", "hdr_iend_hi", "hdr_flags",
        "hdr_kit_lo", "hdr_kit_hi",
    ]
    header = {name: labels[name] for name in needed}
    prelude = (
        "const INSTRUMENTS = " + instruments + ";\n"
        "const PLAYER_BYTES = Uint8Array.from(" + json.dumps(list(player)) + ");\n"
        "const PLAYER_LABELS = " + json.dumps(header) + ";\n"
    )
    return prelude + "\n".join(parts)


def check_midis(src: str, getthem_path: Path) -> None:
    files = {}
    for name in EXPECTED:
        data = (MUSIC / name).read_bytes()
        files[name] = list(data)
    script = src + """
const files = """ + json.dumps(files) + """;
const expected = """ + json.dumps({k: {str(ch): n for ch, n in v.items()} for k, v in EXPECTED.items()}) + """;
for (const [name, bytes] of Object.entries(files)) {
  const song = parseMidi(Uint8Array.from(bytes), name);
  const got = {};
  for (const line of song.lines) got[line.channel] = line.notes.length;
  const want = expected[name];
  for (const [ch, n] of Object.entries(want)) {
    if (got[ch] !== n) throw new Error(name + " ch " + ch + " notes " + got[ch] + " != " + n);
  }
  const bars = barCount(song);
  const width = barTicks(song);
  const expectBars = Math.max(1, Math.ceil(song.maxTick / width));
  if (bars !== expectBars) throw new Error(name + " bars " + bars);
  if (song.ppq !== 350) throw new Error(name + " ppq");
  const arrange = defaultArrangement(song, INSTRUMENTS);
  const perc = song.lines.some(line => line.channel === 9);
  if (perc && arrange.lines[9].voice !== 3) throw new Error(name + " drums not on voice 3");
  if (perc && !arrange.voices[3].percussion) throw new Error(name + " voice 3 not percussion");
  if (!perc && arrange.voices[3].percussion) throw new Error(name + " invented percussion");
  const frames = songFrames(song);
  if (frames < 50) throw new Error(name + " too short");
  const built = buildSid(song, arrange, INSTRUMENTS, PLAYER_BYTES, PLAYER_LABELS);
  if (!built.ok) throw new Error(name + " " + built.error);
  console.log(name + " bars=" + bars + " frames=" + frames + " sid=" + built.parts.total);
  if (name === "GETTHEM.mid") {
    require("fs").writeFileSync(process.env.GETTHEM_SID, Buffer.from(built.bytes));
    const drums = song.lines.find((line) => line.channel === 9);
    const vels = drums.notes.map((note) => note.vel);
    if (Math.min(...vels) > 40 || Math.max(...vels) < 100) {
      throw new Error("GETTHEM drums lost velocity");
    }
    const sec = (drums.notes[0].end - drums.notes[0].start) / song.ppq * 0.5;
    if (sec < 0.02) throw new Error("GETTHEM drum shorter than its note");
  }
}
"""
    print(node_eval(script, {"GETTHEM_SID": str(getthem_path)}))


def check_export(src: str) -> bytes:
    script = src + r"""
const song = {
  name: "TUNE",
  ppq: 350,
  numer: 4,
  denom: 4,
  tempos: [{ tick: 0, us: 500000 }],
  maxTick: 1400,
  lines: [
    { channel: 0, program: 33, notes: [{ start: 0, end: 700, note: 48 }, { start: 700, end: 1400, note: 50 }], bends: [] },
    { channel: 9, program: null, notes: [{ start: 0, end: 70, note: 36 }, { start: 350, end: 420, note: 42 }], bends: [] },
  ],
};
const arrange = defaultArrangement(song, INSTRUMENTS);
const HAT = "HIHAT-SHORT";
arrange.voices[3].kit = { 42: { instrument: HAT } };
const built = buildSid(song, arrange, INSTRUMENTS, PLAYER_BYTES, PLAYER_LABELS);
if (!built.ok) throw new Error(built.error);
if (built.parts.kitSlots !== 2) throw new Error("kit slots " + built.parts.kitSlots);
const b = built.bytes;
if (String.fromCharCode(b[0], b[1], b[2], b[3]) !== "PSID") throw new Error("magic");
const hi = SID_LOAD >> 8;
if (b[8] !== hi || b[9] !== 0x00) throw new Error("load");
if (b[10] !== hi || b[11] !== 0x00) throw new Error("init");
if (b[12] !== hi || b[13] !== 0x03) throw new Error("play");
const body = b.slice(0x7c);
let stores = 0;
for (let i = 0; i < body.length - 2; i++) {
  if (body[i] === 0x8d && body[i + 1] === 0x18 && body[i + 2] === 0xd4) stores++;
}
if (stores !== 1) throw new Error("STA $D418 x" + stores);
if (arrange.lines[9].voice !== 3) throw new Error("synth drums");
// First frame of each hit loads that slot's own attack/decay; the hard
// restart happens in the gate-off frames before it.
const hrAd = (id) => hexToBytes(INSTRUMENTS.find((item) => item.id === id).raw)[3];
const m = new SidMachine(44100);
m.load(body);
let heard = 0;
let percOn = 0;
let percOff = 0;
const adAt = {};
for (let i = 0; i < 80; i++) {
  m.playFrame();
  const v = m.sid.voices;
  if (v.some((voice) => voice.gate && voice.freq)) heard++;
  if (v[2].gate) percOn++;
  else percOff++;
  if (i === 0 || i === 25) adAt[i] = (v[2].attack << 4) | v[2].decay;
}
if (heard < 10) throw new Error("player stayed silent");
if (percOn < 2 || percOff < 2) throw new Error("drums stayed " + (percOn ? "on" : "off"));
if (adAt[0] !== hrAd(arrange.voices[3].instrument)) throw new Error("kick slot AD " + adAt[0].toString(16));
if (adAt[25] !== hrAd(HAT)) throw new Error("hat slot AD " + adAt[25].toString(16));
console.log("export bytes=" + b.length + " body=" + body.length + " heard=" + heard + " kit=" + built.parts.kitSlots);
process.stdout.write(Buffer.from(b).toString("base64"));
"""
    text = node_eval(script)
    lines = text.strip().splitlines()
    print(lines[0])
    import base64
    return base64.b64decode(lines[-1])


def check_genmusic(psid: bytes, stem: str = "tune") -> None:
    sidreloc_env()
    import genmusic
    with tempfile.TemporaryDirectory(prefix="wolf_sid_") as tmp:
        folder = Path(tmp)
        (folder / f"{stem}.sid").write_bytes(psid)
        out = folder / "out"
        out.mkdir()
        genmusic.MUSIC = folder
        genmusic.OUT_DIR = out
        genmusic.ASM_OUT = out / "menu_tracks.asm"
        try:
            genmusic.main()
        except ValueError as exc:
            if "not in the subpath" not in str(exc):
                raise
        prg = (out / "mus1.prg").read_bytes()
        load = prg[0] | (prg[1] << 8)
        if load != genmusic.LOAD:
            raise SystemExit(f"relocated load is ${load:04X}")
        end = load + len(prg) - 2
        if end > genmusic.LIMIT:
            raise SystemExit(f"image ends ${end:04X}")
        print(f"genmusic mus1 ${load:04X}-${end - 1:04X}")


def main() -> None:
    src = load_js()
    with tempfile.TemporaryDirectory(prefix="wolf_getthem_") as tmp:
        getthem = Path(tmp) / "GETTHEM.sid"
        check_midis(src, getthem)
        check_genmusic(getthem.read_bytes(), "GETTHEM")
    psid = check_export(src)
    check_genmusic(psid)
    print("test_music_editor: ok")


if __name__ == "__main__":
    main()
