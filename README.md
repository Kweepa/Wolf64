# Wolf64

Unofficial Commodore 64 fan port of Wolfenstein 3D. Not affiliated with or endorsed by id Software or ZeniMax. For non-commercial / fan use only.

## Build

Requires [ACME](https://sourceforge.net/projects/acme-crossass/), Python 3, and [VICE](https://vice-emu.sourceforge.io/) (`c1541` for disk creation). Set paths in `setup-env.bat` if needed.

```bat
build.bat    rem produces wolf64.d64 (KERNAL) and wolf64-krill.d64
make.bat     rem build + launch KERNAL disk in VICE
run-game.bat         rem launch wolf64.d64 (VICE virtual device traps)
run-game.bat krill   rem launch wolf64-krill.d64 (true drive emulation)
```

The Krill disk needs a real 1541-class drive or VICE true drive emulation (`run-game.bat krill` turns traps off and TDE on). Virtual device traps will not run drive code. EasyFlash stays on the KERNAL disk. Rebuild Krill binaries with `python tools/build_krill.py` only when the resident address or `krill/config` changes.

## EasyFlash cartridge

To pack the disk image into an EasyFlash `.crt` for real hardware or emulation:

1. Download **Disk2Easyflash v1.1** from [milasoft64/Disk2Easyflash-v1](https://github.com/milasoft64/Disk2Easyflash-v1) (file: `v1.1/disk2easyflash_v1.1.py`) or [CSDb](https://csdb.dk/release/?id=260920).
2. Save it as `3rdparty/disk2easyflash.py`. Keep this file locally for `make-cart.bat`; the whole `3rdparty/` directory is gitignored and not pushed to GitHub.
3. Run after building the disk:

```bat
build.bat
make-cart.bat
```

Output: `wolf64.crt`.

### Third-party tool — Disk2Easyflash

`3rdparty/disk2easyflash.py` is **not included** in this repository (kept separate from the project's own `tools/` scripts). Obtain it from upstream:

- **v1.1 (recommended):** [GitHub — milasoft64/Disk2Easyflash-v1](https://github.com/milasoft64/Disk2Easyflash-v1) / [CSDb release](https://csdb.dk/release/?id=260920) — enhancements by MilaSoft
- **Original logic:** [alexkazik/disk2easyflash](https://github.com/alexkazik/disk2easyflash) — licensed under [0BSD](https://opensource.org/license/0bsd)

MilaSoft's v1.1 release does not declare a separate license on GitHub; the original Alex Kazik code is 0BSD. The EasyFlash cart is built from the KERNAL disk (`wolf64.d64`); Krill drive code is 1541-only.

## Docs

- [MEMORY_MAP.md](MEMORY_MAP.md) — C64 RAM table, boot overlays, disk files
- [TechDesignDoc.md](TechDesignDoc.md) — architecture (early design; prefer MEMORY_MAP / TechNotes for addresses)
- [TechNotes.md](TechNotes.md) — banking, disk layout, loader details
- [MapFormat.md](MapFormat.md) — map file format
- [krill/README.md](krill/README.md) — Krill v194 rebuild (resident `$4E00`)
