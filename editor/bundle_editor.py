#!/usr/bin/env python3
"""Bundle the music editor into editor/index.html (no server)."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "index.html"
PLAYER = ROOT / "player.asm"
JS_ORDER = [
    "js/midi.js",
    "js/sidexport.js",
    "js/cpu6502.js",
    "js/sidchip.js",
    "js/sidmachine.js",
    "js/stave.js",
    "js/playback.js",
    "js/io.js",
    "js/main.js",
]
HEADER_LABELS = [
    "hdr_vptr_lo", "hdr_vptr_hi", "hdr_vend_lo", "hdr_vend_hi",
    "hdr_iptr_lo", "hdr_iptr_hi", "hdr_iend_lo", "hdr_iend_hi", "hdr_flags",
    "hdr_kit_lo", "hdr_kit_hi",
]


def parse_labels(text: str) -> dict[str, int]:
    out = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1] == "=" and parts[2].startswith("$"):
            out[parts[0]] = int(parts[2][1:], 16)
    return out


def assemble() -> tuple[bytes, dict[str, int]]:
    acme = os.environ.get("ACME")
    if not acme:
        found = shutil.which("acme") or shutil.which("acme.exe")
        acme = found or ""
    lbl = ROOT / "player.lbl"
    blob = ROOT / "player.bin"
    if acme and Path(acme).is_file() and PLAYER.is_file():
        cmd = [
            acme, "--format", "plain",
            "-o", str(blob),
            "-l", str(lbl),
            str(PLAYER),
        ]
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if proc.returncode != 0:
            msg = (proc.stderr or proc.stdout or "acme failed").strip()
            raise SystemExit(msg)
    if not blob.is_file() or not lbl.is_file():
        raise SystemExit("player.bin missing and ACME is not available")
    return blob.read_bytes(), parse_labels(lbl.read_text(encoding="latin1"))


def main() -> None:
    css = (ROOT / "styles.css").read_text(encoding="utf-8")
    js = "\n\n".join((ROOT / rel).read_text(encoding="utf-8") for rel in JS_ORDER)
    instruments = json.loads((ROOT / "instruments.json").read_text(encoding="utf-8"))
    player, labels = assemble()
    missing = [name for name in HEADER_LABELS + ["player_base"] if name not in labels]
    if missing:
        raise SystemExit(f"player labels missing: {', '.join(missing)}")
    m = re.search(r"const SID_LOAD = 0x([0-9a-fA-F]+);", js)
    if not m or int(m.group(1), 16) != labels["player_base"]:
        raise SystemExit(f"player.asm origin ${labels['player_base']:04X} does not match SID_LOAD in sidexport.js")
    needed = HEADER_LABELS
    header = {name: labels[name] for name in needed}
    data_js = (
        "const INSTRUMENTS = " + json.dumps(instruments) + ";\n"
        "const PLAYER_BYTES = Uint8Array.from(" + json.dumps(list(player)) + ");\n"
        "const PLAYER_LABELS = " + json.dumps(header) + ";\n"
    )
    # Constants have to exist before main.js runs. Split the last module off.
    head, _, tail = js.rpartition("// split-before-main")
    if not head:
        pre, main_src = js.rsplit("let musicDir", 1)
        main_src = "let musicDir" + main_src
    else:
        pre, main_src = head, tail
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Wolf64 Music</title>
  <style>
{css}
  </style>
</head>
<body>
  <header class="toolbar">
    <h1>Wolf64</h1>
    <div class="toolbar-actions">
      <button type="button" id="btn-folder">Music folder</button>
      <button type="button" id="btn-midi">Play MIDI</button>
      <button type="button" id="btn-sid">Play SID</button>
      <button type="button" id="btn-stop">Stop</button>
      <button type="button" id="btn-export">Export SID</button>
    </div>
    <p id="status" class="status" role="status"></p>
  </header>
  <main class="layout">
    <aside class="left">
      <h2>Songs</h2>
      <ul id="song-list" class="song-list"></ul>
      <div class="toolbar-actions">
        <button type="button" id="btn-song">Song</button>
      </div>
      <h2>Lines</h2>
      <ul id="line-list" class="line-list"></ul>
    </aside>
    <section class="center">
      <div class="center-heading">
        <h2>Stave</h2>
        <p id="score-meta"></p>
      </div>
      <div class="score-scroll" id="score-scroll">
        <div class="score-stack">
          <canvas id="score"></canvas>
          <canvas id="playhead"></canvas>
        </div>
      </div>
      <p class="hint">Click a line to edit it. Shared SID voices are merged. Drums stay on one voice.</p>
    </section>
    <aside class="right">
      <div class="inspector" id="inspector"></div>
    </aside>
  </main>
  <div class="file-gate" id="file-gate">
    <div class="file-gate-card">
      <h2>Open the music folder</h2>
      <p>Choose the Wolf64 <code>music</code> folder. MIDI files stay untouched. Mute, merge, and instrument choices are saved beside them.</p>
      <button type="button" id="btn-gate" class="file-gate-primary">Choose folder</button>
    </div>
  </div>
  <script>
{data_js}
{pre}
{main_src}
  </script>
</body>
</html>
"""
    OUT.write_text(html, encoding="utf-8")
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes, {len(instruments)} instruments)")


if __name__ == "__main__":
    main()
