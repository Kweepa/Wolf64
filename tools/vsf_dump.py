"""Dump CPU state + stack from a VICE .vsf snapshot, resolving addresses via .lbl files."""
import sys, struct

def read_modules(data):
    # Header: "VICE Snapshot File\x1a" (19) + major + minor + machine name (16)
    assert data[:19] == b"VICE Snapshot File\x1a", "not a VICE snapshot"
    off = 19 + 2 + 16
    if data[off:off+13] == b"VICE Version\x1a":
        off += 13 + 4 + 4  # magic + version + svn rev
    mods = {}
    while off + 22 <= len(data):
        name = data[off:off+16].split(b"\0")[0].decode("ascii", "replace")
        size = struct.unpack("<I", data[off+18:off+22])[0]
        if size < 22 or off + size > len(data):
            break
        mods[name] = data[off+22:off+size]
        off += size
    return mods

def load_labels(paths):
    labels = {}
    for p in paths:
        try:
            for line in open(p):
                parts = line.split()
                # VICE format: al C:089d .label
                if len(parts) >= 3 and parts[0] == "al":
                    addr = int(parts[1].split(":")[-1], 16)
                    labels.setdefault(addr, []).append(parts[2].lstrip("."))
        except FileNotFoundError:
            pass
    return labels

def resolve(addr, labels):
    # nearest label at or below addr, within 0x400
    best = None
    for a in range(addr, max(-1, addr - 0x400), -1):
        if a in labels:
            best = (a, labels[a])
            break
    if best is None:
        return "?"
    a, names = best
    name = "/".join(n for n in names if not n.startswith("__")) or "/".join(names)
    d = addr - a
    return name + (f"+{d:#x}" if d else "")

def main():
    snap = sys.argv[1]
    lbl_files = sys.argv[2:]
    data = open(snap, "rb").read()
    mods = read_modules(data)
    print("modules:", ", ".join(f"{k}({len(v)})" for k, v in mods.items()))
    labels = load_labels(lbl_files)

    cpu = mods.get("MAINCPU") or mods.get("MAINC64CPU")
    if cpu:
        clk = struct.unpack("<Q", cpu[0:8])[0]
        ac, xr, yr, sp = cpu[8], cpu[9], cpu[10], cpu[11]
        pc = struct.unpack("<H", cpu[12:14])[0]
        st = cpu[14]
        flags = "".join(f if (st >> (7-i)) & 1 else "." for i, f in enumerate("NV-BDIZC"))
        print(f"\nPC={pc:04x} ({resolve(pc, labels)})  A={ac:02x} X={xr:02x} Y={yr:02x} SP={sp:02x} ST={st:02x} [{flags}] CLK={clk}")

    mem = mods.get("C64MEM")
    if mem:
        # C64MEM: cpudata, cpudir, exrom, game, then 64KB ram (possibly trailing fields)
        ram = mem[4:4+65536]
        print(f"$01 (cpu port) = {mem[0]:02x}")
        if cpu:
            lo = max(0, pc - 16)
            print(f"\nRAM around PC ({lo:04x}-{pc+15:04x}):")
            print(" ", ram[lo:pc].hex(" "), "|", ram[pc:pc+16].hex(" "))
            # stack scan for possible return addresses
            print(f"\nStack $01{sp+1:02x}-$01ff (word candidates, ret = addr-2):")
            for i in range(sp + 1, 0x100 - 1):
                w = ram[0x100 + i] | (ram[0x100 + i + 1] << 8)
                tgt = w - 2
                r = resolve(tgt, labels)
                if r != "?" and 0x0400 <= tgt <= 0xffff:
                    print(f"  $01{i:02x}: {w:04x}  ret->{tgt:04x} {r}")
            print("\nraw stack:", ram[0x100 + sp + 1:0x200].hex(" "))
        # zero page
        print("\nZP $00-$7f:")
        for base in range(0, 0x80, 16):
            print(f"  {base:02x}: {ram[base:base+16].hex(' ')}")

if __name__ == "__main__":
    main()
