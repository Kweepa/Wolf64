# Krill loader v194 — prebuilt for Wolf64

Binaries only; the loader source is not vendored here. Rebuild with:

    python tools/build_krill.py

which fetches [CSDb #226124](https://csdb.dk/release/?id=226124) into a temp
folder and runs:

    make -C src PLATFORM=c64 prg INSTALL=2000 RESIDENT=4e00 ZP=60 \
         EXTCONFIGPATH=<repo>/krill/config

with [`krill/config/loaderconfig.inc`](config/loaderconfig.inc): `LOAD_TO_API = 1`,
`UNINSTALL_API = 0`, `DECOMPRESSOR = NONE`, `LOAD_COMPD_API = 0`; everything
else stock.

| file | load address | notes |
|---|---|---|
| `loader.prg` | `$4E00` | resident (~236 B). Hole after SFX, before weapons. Boot KERNAL-loads it. |
| `install.prg` | `$2000` | transient. Run once at splash; MENU overwrites it. |
| `loadersymbols-c64.inc` | — | the build's own symbol/config dump. |

`$4E00` is always RAM (VIC bank 1, unused by bitmap/matrices). `$01` must still
be `$35` around `jsr loadraw` (IEC `$DD00`), under `SEI`. Do not `IOINIT` while
drive code is up (`$DD02=$3F` tears it down). Absolute `$dd00` writes only.
