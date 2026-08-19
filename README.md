# Wolf64

Unofficial Commodore 64 fan port of Wolfenstein 3D. Not affiliated with or endorsed by id Software or ZeniMax. For non-commercial / fan use only.

## Build

Requires [ACME](https://sourceforge.net/projects/acme-crossass/), Python 3, and [VICE](https://vice-emu.sourceforge.io/) (`c1541` for disk creation). Set paths in `setup-env.bat` if needed.

```bat
build.bat    rem produces wolf64.d64
make.bat     rem build + launch in VICE
```

## EasyFlash cartridge

To pack the disk image into an EasyFlash `.crt` for real hardware or emulation:

1. Download **Disk2Easyflash v1.1** from [milasoft64/Disk2Easyflash-v1](https://github.com/milasoft64/Disk2Easyflash-v1) (file: `v1.1/disk2easyflash_v1.1.py`) or [CSDb](https://csdb.dk/release/?id=260920).
2. Save it as `tools/disk2easyflash.py`. Keep this file locally for `make-cart.bat`; it is gitignored and not pushed to GitHub.
3. Run after building the disk:

```bat
build.bat
make-cart.bat
```

Output: `wolf64.crt`.

### Third-party tool — Disk2Easyflash

`tools/disk2easyflash.py` is **not included** in this repository. Obtain it from upstream:

- **v1.1 (recommended):** [GitHub — milasoft64/Disk2Easyflash-v1](https://github.com/milasoft64/Disk2Easyflash-v1) / [CSDb release](https://csdb.dk/release/?id=260920) — enhancements by MilaSoft
- **Original logic:** [alexkazik/disk2easyflash](https://github.com/alexkazik/disk2easyflash) — licensed under [0BSD](https://opensource.org/license/0bsd)

MilaSoft's v1.1 release does not declare a separate license on GitHub; the original Alex Kazik code is 0BSD. Wolf64 uses standard KERNAL `LOAD` only, which Disk2Easyflash supports.

## Docs

- [TechDesignDoc.md](TechDesignDoc.md) — architecture and memory map
- [TechNotes.md](TechNotes.md) — banking, disk layout, loader details
- [MapFormat.md](MapFormat.md) — map file format
