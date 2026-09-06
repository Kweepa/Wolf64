# Wolf64 memory map

Snapshot of C64 RAM after **boot → MENU → locode + assets → `LoadLevel`** has finished and the game is running (`$01 = $34`: BASIC and KERNAL out, I/O out — all 64K DRAM). Addresses from `mem.asm`, `zp.asm`, `wolf64.asm`, `boot.asm`, `menu.asm`, and `generated/wolf64.lbl` (rebuild refreshes labels).

Two disks from `build.bat`: **`wolf64.d64`** (KERNAL `$FFD5`, VICE virtual traps) and **`wolf64-krill.d64`** (`-DUSE_KRILL=1`, native Krill 236 B at `$4E00`). Autostart name is **`wolf64`** (`boot.prg`). `run-game.bat` launches the KERNAL disk; `run-game.bat krill` the Krill disk (true drive emulation). [TechNotes.md](TechNotes.md) covers `$01` banking and the load recipe.

## Boot sequence

1. BASIC `LOAD"WOLF64",8,1` → `$0801` / SYS 2061 → `$080D`. `$01=$36`, `IOINIT`, DEN off.
2. KERNAL-load **`splashc`** at `$8000` (matrix in place, colour staged `$83E8`, `do_splash` at `$87D1`). `JSR do_splash`: colour → `$D800`, clear bitmap, VIC bank `$8000` MCM on.
3. KERNAL-load **`splash`** at `$A000` (bitmap paints in already coloured).
   - **Krill disk:** KERNAL-load **`loader`** at `$4E00` and **`install`** at `$2000`, `JSR install`, absolute `$dd00=VIC_BANK_DD00` (`%01`), then `loadraw` **`menu`**.
   - **KERNAL disk:** KERNAL-load **`menu`** at `$0900`. Restore `$dd00` after each KERNAL LOAD (RMW of `$dd00` during IEC).
4. Boot `JSR $0900` — difficulty select. MENU draws hires over the cover (sprites at `BJH_SPRITES` `$8800`). Selectors: `effects_vol` `$08FD`, `game_complete` `$08FE`, `difficulty` `$08FF`.
5. Remaining files via `loadraw` (Krill, `$01=$35`, no `IOINIT`) or KERNAL SETNAM/SETLFS/LOAD: `locode`, `scr`, `sfx`, `bjh`, `wpn`, `itm`, `egfx`, `bmp`, `sqt`, `texlo`, `paint`, `tab`, `col`. **LOCODE** overwrites MENU at `$0900` (enemy code is in locode; no stage/copy).
6. `TXS $FF`, `JMP $0900` (`locode_entry`): `install_sqtabs` (SQT `$C000`→`$D000`), `LoadLevel` → **`e1m1`** at `$C000`, `game_start`.

Game over (lives expired) jumps `$08C0` → `reboot_game` (in locode): `IOINIT` (tears down Krill), KERNAL-load **`wolf64`**, `JMP $080D`. Deaths with lives remaining `restart_level` (reload map only). On the Krill disk, **never `IOINIT`/`RESTOR` on the in-play `LoadLevel` path**. Krill ZP is `$60`–`$64` (`view_row8–10` scratch; dead across a load).

**Selectors that survive locode / reboot LOAD** (boot must not emit `$08FD–$08FF`):

| Addr | Symbol |
|------|--------|
| `$08C0` | `REBOOT_STUB` — 3-byte `JMP reboot_game` (installed at `locode_entry`) |
| `$08FD` | `effects_vol` |
| `$08FE` | `game_complete` |
| `$08FF` | `difficulty` |

`episode` / `level_num` / `secret_from` live in **low BSS** (KERNAL LOAD can see them). QS copies them into `GAME_STATE` around save/load. They are **not** preserved across reboot.

**Menu VIC** (while `menu.prg` is resident): hires bitmap, VIC bank `$8000`, matrix `$8000`, bitmap `$A000`. Logo / hint / cursor sprites at `$8800`…. Play uses the same bank, MCM bitmap, double-buffered matrices.

---

## Per-kilobyte map (game running)

Sizes drift; prefer symbols in `generated/wolf64.lbl`. Ranges inclusive of start; `end_*` exclusive.

| KB | Range | Contents |
|----|-------|----------|
| 0 | `$0000`–`$03FF` | CPU port, game ZP, under-stack BSS, cassette BSS `$033C`. |
| 1 | `$0400`–`$07FF` | **`tab`** |
| 2 | `$0800`–`$08FF` | Low BSS overlay; `REBOOT_STUB`; selectors `$08FD`–`$08FF`. |
| 2–18 | `$0900`–`$4804` | **`locode`** — all game code (incl. enemy*.asm + items_draw). |
| 18–19 | `$4805`–`$4C63` | **`sfx`** (in locode→Krill gap). Slack → `$4DFF`. |
| 19 | `$4E00`–`$4FFF` | **Krill hole** (loadraw on Krill disk; reserved on both). |
| 20–31 | `$5000`–`$7F35` | **`paint`** then **`egfx`** (enemy pixels). ~202 B free → `$8000`. |
| 32–39 | `$8000`–`$9FFF` | **VIC bank**: `scr` A/B, BJH, WPN_STAGE; `$9000` hole: WPN_MASTER + `itm` + **`GAME_STATE`** (pre-bitmap). |
| 40–47 | `$A000`–`$BFFF` | **`bmp`** MCM 8K (+ score hole + hexfont). |
| 48–51 | `$C000`–`$CFFF` | **`MAP`** 4K (disk: `e1m*`; also SQT load staging). |
| 52–55 | `$D000`–`$DFFF` | **`sqt`** 2K @ `$D000` + item/vis scratch @ `$D800` (`$01=$34`). |
| 56–63 | `$E000`–`$FFFF` | **`TEX_LO`** / **`TEX_HI`** (derived); IRQ vectors rewritten after `init_tex_hi`. |

Quicksave (F5/F7): two KERNAL files — **`QS`** = `GAME_STATE` (863 B), **`QM`** = `MAP` (4K). DEN=0; checksum in QS header covers GS body + map.

---

## Major regions (summary)

| Range | Role |
|-------|------|
| `$0002`–`$00FF` | Zero page (`zp.asm`) |
| `$0100`–`$01CF` | Under-stack BSS (`vis_slot` / `vis_perp_*`). `STACK_GUARD` `$01D0`. |
| `$033C`–`$03FC` | Tape BSS (temps only; not saveable) |
| `$0400`–`$07D2` | Render tables (`tab`) |
| `$0801`–… | Low BSS overlay (was boot); `load_in_play` |
| `$08C0` / `$08FD`–`$08FF` | Reboot stub + menu selectors |
| `$0900`–`$4804` | Locode (all game code) |
| `$4805`–`$4C63` | PC SFX |
| `$4E00`–`$4FFF` | Krill reserved |
| `$5000`–`$6C91` | Wall painters |
| `$6C92`–`$7F35` | Enemy pixel gfx |
| `$8000`–`$87E7` | VIC matrices A/B |
| `$8800`–… | BJH HUD sprites + `WPN_STAGE` (12×64; body + both chaingun flashes) |
| `$9000`–… | Char-ROM hole for VIC; `WPN_MASTER` + item gfx + `GAME_STATE` (CPU) |
| `$A000`–`$BF3F` | MCM bitmap |
| `$C000`–`$CFFF` | `MAP` |
| `$D000`–`$D7FF` | Judd SQTAB |
| `$D800`–… | Item/vis scratch (`$01=$34`) |
| `$E000`–`$EFFF` | `TEX_LO` |
| `$F000`–`$FFFF` | `TEX_HI` (derived) |

---

## Disk files

| DOS name | Load | Notes |
|----------|------|--------|
| `wolf64` | `$0801` | boot |
| `loader` / `install` | `$4E00` / `$2000` | Krill disk only |
| `splashc` | `$8000` | matrix + colour + `do_splash` |
| `splash` | `$A000` | 8000-byte MCM bitmap |
| `menu` | `$0900` | overwritten by locode |
| `locode` | `$0900` | all game code |
| `scr` / `bjh` / `wpn` / `itm` | VIC bank | |
| `sfx` | `end_locode` | pre-Krill gap |
| `paint` / `egfx` | `$5000` / after paint | |
| `bmp` | `$A000` | |
| `sqt` | `$C000` | copied to `$D000` by `install_sqtabs` |
| `texlo` | `$E000` | |
| `tab` / `col` | `$0400` / `$D800` | |
| `e1m1`…`e1ms` | `$C000` | |

`TEX_HI` is RAM-only. Quicksave uses disk files **`QS`** + **`QM`**.

---

## Low BSS overlay (`$0801`, after boot)

| Symbol | Notes |
|--------|--------|
| `col_texid`…`col_wallz_l` | 4×40 column buffers |
| `load_*` | LoadPrg name scrap |
| `load_in_play` | in-play LoadLevel / QS flag |
| `end_bss` | must be ≤ `REBOOT_STUB` |

`episode` / `level_num` / `secret_from` / `load_in_play` follow the load-name scrap (KERNAL-visible).

---

## GAME_STATE (after `end_itm`, 863 B)

Live saveable slab / **`QS`** file body (MAP is separate **`QM`** file @ `$C000`):

| Offset | Contents |
|--------|----------|
| +0 | Header (magic `W64S`, version 3, checksum over GS body + MAP) |
| +7 | Player blob (23 B); ZP/`difficulty` mirrors patched around I/O |
| +30 | Doors (8×8) |
| +94 | `enemy_count` |
| +95 | 12×64 enemy SoA (`enemy_xh`…`enemy_burst`) |

---

## VIC graphics (bank `$8000`, play)

`$DD00` bits 0–1 = `%01` → `$8000–$BFFF`. `$d018` `%00001000` / `%00011000` (matrix A/B, bitmap `$A000`). Same relative nibbles as the old `$4000` bank.

| Resource | Address |
|----------|---------|
| Matrix A / B | `$8000` / `$8400` |
| Sprite pointers | `SCREEN+$3F8` / `SCREEN_B+$3F8` |
| BJ-head HUD sprites | `$8800`… |
| Weapon stage (≤12 frames; ≤8 visible) | after BJH, under `$9000` |
| Weapon master (all frames) | `$9000`… (CPU; VIC sees char ROM) |
| Item gfx + `GAME_STATE` | after WPN master (CPU) |
| Bitmap | `$A000`–`$BF3F` |
| Colour RAM | `$D800`–`$DBE7` (I/O in only; scratch uses this RAM at `$01=$34`) |

---

## `$01` (play)

| Value | Use |
|-------|--------|
| `$34` | Default play / render (`TEX_*`, `SQTAB`, scratch, `MAP` as RAM) |
| `$35` | Chip touch: VIC, SID, CIA, colour RAM; Krill loadraw |
| `$36` | KERNAL LOAD/SAVE |

IRQ/NMI save `$01`, set `$35`, ack, restore. Play IRQ is CIA1 Timer A (input/SFX) plus VIC raster mux (HUD faces at raster 40, weapons at 88).

---

## Free scrap (this build, approximate)

| Range | Notes |
|-------|--------|
| Locode → Krill | ACME `!warn` after locode / after SFX |
| Paint/egfx → `$8000` | ~202 B |
| After `itm` → bitmap | scratch BSS + slack |
| Locode → Krill | ACME `!warn` after locode / after SFX |
| Paint/egfx → `$8000` | ~202 B |
| After GAME_STATE → bitmap | slack before `$A000` |
| `$FF00`–`$FFF9` | above map; keep vectors |

Assemble overlap errors: locode/SFX vs `KRILL_HOLE`, paint/egfx vs `SCREEN`, itm/`GAME_STATE` vs `BITMAP`, tape vs `$03FC`, stack vs `$01D0`.

Sources: `wolf64.asm`, `mem.asm`, `zp.asm`, `boot.asm`, `menu.asm`, `loader.asm`, `vic.asm`, `generated/wolf64.lbl`.
