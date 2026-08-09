#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

from py65.devices.mpu6502 import MPU

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    addrs = {}
    for line in (ROOT / "wolf64.lbl").read_text().splitlines():
        m = re.match(r"al C:([0-9a-fA-F]+) \.(\S+)", line)
        if m:
            addrs[m.group(2)] = int(m.group(1), 16)
    data = (ROOT / "wolf64.prg").read_bytes()
    load = data[0] + data[1] * 256
    body = data[2:]
    mpu = MPU()
    mem = mpu.memory
    for i, b in enumerate(body):
        if load + i < 65536:
            mem[load + i] = b
    mem[0x00] = 0x2F
    mem[0x01] = 0x37
    mem[0xDD02] = 0x3F
    mem[0xDD00] = 0xC7
    mem[0xD011] = 0x1B
    mpu.pc = addrs["start"]
    mpu.sp = 0xFF
    hits = 0
    for _ in range(5_000_000):
        if mpu.pc == addrs["main_loop"]:
            hits += 1
            if hits >= 2:
                break
        mpu.step()
    print(f"hits={hits} $01={mem[1]:02x}")
    print(
        f"d011=${mem[0xD011]:02x} d018=${mem[0xD018]:02x} dd00=${mem[0xDD00]:02x}"
    )
    scr = bytes(mem[0x4000 : 0x4000 + 1000])
    print("SCREEN $4000 nonzero", sum(1 for b in scr if b), "row1", scr[40:80].hex())
    print("BITMAP $6000", bytes(mem[0x6000:0x6010]).hex())
    print("FB $E000", bytes(mem[0xE000:0xE018]).hex())
    print("MAP $5000", bytes(mem[0x5000:0x5008]).hex())


if __name__ == "__main__":
    main()
