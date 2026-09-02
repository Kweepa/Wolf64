# Wolf64 memory map

Snapshot of C64 RAM after **boot → MENU → ENEMY copy → locode + assets → `LoadLevel`** has finished and the game is running (`$01 = $34`: BASIC and KERNAL out, I/O out — all 64K DRAM). Addresses from `mem.asm`, `zp.asm`, `wolf64.asm`, `boot.asm`, `menu.asm`, and `generated/wolf64.lbl` (rebuild refreshes labels).

Two disks from `build.bat`: **`wolf64.d64`** (KERNAL `$FFD5`, VICE virtual traps) and **`wolf64-krill.d64`** (`-DUSE_KRILL=1`, native Krill 236 B at `$4E00`). Autostart name is **`wolf64`** (`boot.prg`). `run-game.bat` launches the KERNAL disk; `run-game.bat krill` the Krill disk (true drive emulation). [TechNotes.md](TechNotes.md) covers `$01` banking and the load recipe.

## Boot sequence

1. BASIC `LOAD"WOLF64",8,1` → `$0801` / SYS 2061 → `$080D`. `$01=$36`, `IOINIT`, DEN off.
2. KERNAL-load **`splashc`** at `$4000` (matrix in place, colour staged `$43E8`, `do_splash` at `$47D1`). `JSR do_splash`: colour → `$D800`, clear bitmap, VIC bank 1 MCM on.
3. KERNAL-load **`splash`** at `$6000` (bitmap paints in already coloured).
   - **Krill disk:** KERNAL-load **`loader`** at `$4E00` and **`install`** at `$2000`, `JSR install`, absolute `$dd00=%00000010`, then `loadraw` **`menu`**.
   - **KERNAL disk:** KERNAL-load **`menu`** at `$0900`. Restore `$dd00` bank 1 after each KERNAL LOAD (RMW of `$dd00` during IEC).
4. Boot `JSR $0900` — difficulty select. MENU draws hires over the cover (sprites at `$4800`). Selectors: `effects_vol` `$08FD`, `game_complete` `$08FE`, `difficulty` `$08FF`.
5. Boot stages **`enemy`** at `PAINTERS` (`$A000`, PRG header `$A000`), `JSR MENU+3` (`copy_enemy` → `$C000` at `$01=$34`, high→low because staging overlaps the destination). The enemy block **spans `$D000–$DFFF`**; it cannot load there with I/O visible.
6. Remaining files via `loadraw` (Krill, `$01=$35`, no `IOINIT`) or KERNAL SETNAM/SETLFS/LOAD: `locode`, `scr`, `sfx`, `bjh`, `wpn`, `itm`, `bmp`, `sqt`, `texlo`, `paint`, `tab`, `col`. **LOCODE** overwrites MENU at `$0900`.
7. `TXS $FF`, `JMP $0900` (`locode_entry`): install `REBOOT_STUB`, `LoadLevel` → **`e1m1`** at `$EF00`, `game_start`.

Game over (lives expired) jumps `$08C0` → `reboot_game` (in the enemy block): `IOINIT` (tears down Krill), KERNAL-load **`wolf64`**, `JMP $080D`. Deaths with lives remaining `restart_level` (reload map only). On the Krill disk, **never `IOINIT`/`RESTOR` on the in-play `LoadLevel` path**. Krill ZP is `$60`–`$64` (`view_row8–10` scratch; dead across a load).

**Selectors that survive locode / reboot LOAD** (boot must not emit `$08FD–$08FF`):

| Addr | Symbol |
|------|--------|
| `$08C0` | `REBOOT_STUB` — 3-byte `JMP reboot_game` (installed at `locode_entry`) |
| `$08FD` | `effects_vol` |
| `$08FE` | `game_complete` |
| `$08FF` | `difficulty` |

`episode` / `level_num` live in low BSS (`$0801`…) and are **not** preserved across reboot.

**Menu VIC** (while `menu.prg` is resident): hires bitmap, bank 1, matrix `$4000`, bitmap `$6000`. Logo / hint / cursor sprites `$4800`–`$4C3F` (17×64). Menufont occupies `$3800` until **`sqt`** replaces it. Play uses the same bank, MCM bitmap, double-buffered matrices.

---

## Per-kilobyte map (game running)

Sizes are noted when a region does **not** fill the whole 1K. Ranges are inclusive of the start; `end_*` labels are exclusive. Code entry addresses drift; prefer symbols in `generated/wolf64.lbl`.

| KB | Range | Contents |
|----|-------|----------|
| 0 | `$0000`–`$03FF` | CPU port, game ZP, under-stack BSS, page-2 KERNAL scrap during LOAD, cassette BSS `$033C`–`$03EB`. |
| 1 | `$0400`–`$07FF` | **`tab`** `$0400`–`$07D2` (979 B). ~46 B free `$07D3`–`$0800`. |
| 2 | `$0800`–`$08FF` | Boot was here; **low BSS** `$0801`–`$08A9` (`col_*`, load scrap). `REBOOT_STUB` `$08C0`. Selectors `$08FD`–`$08FF`. |
| 2–11 | `$0900`–`$26A0` | **`locode`** (7585 B). Free `$26A1`–`$2FFF` to SFX. |
| 12–13 | `$3000`–`$345E` | **`sfx`** (1119 B). Slack `$345F`–`$37FF` to SQTAB. |
| 14–15 | `$3800`–`$3FFF` | **`sqt`** Judd tables (2K). |
| 16–17 | `$4000`–`$47E7` | **`scr`**: matrix A `$4000`, 24-byte sprite-ptr pad, matrix B `$4400`. |
| 18–19 | `$4800`–`$4A85` | **`bjh`** 10 HUD face sprites (640 B + ptr tables). Slack `$4A86`–`$4DFF`. **Krill `loadraw` `$4E00`–`$4EEB`** on **`wolf64-krill.d64`** only (reserved hole on both disks). |
| 20–21 | `$5000`–`$587F` | **`wpn`** HUD sprites (34×64). |
| 22–23 | `$5880`–`$5FD7` | **`itm`** world item gfx. `col_enemy` `$5FD8`–`$5FFF` (40 B). |
| 24–31 | `$6000`–`$7FFF` | **`bmp`** MCM bitmap `$6000`–`$7F3F`; score code hidden at `$64B0`; hexfont `$7F40`–`$7FBF`. `$7FC0`–`$7FFF` leftover. |
| 32–35 | `$8000`–`$8FFF` | **`texlo`** — `TEX_LO` 4K. |
| 36–39 | `$9000`–`$9FFF` | **`TEX_HI`** 4K, RAM-only (`init_tex_hi` from `TEX_LO`; not a disk file). |
| 40–47 | `$A000`–`$BC91` | **`paint`** wall-height painters (7314 B). Then `col_wallz_h` + item/vis/cold-enemy SoA → `$BF09`. ~246 B free `$BF0A`–`$BFFF`. |
| 48–59 | `$C000`–`$EECC` | **`enemy`** code+gfx+hot SoA (11981 B), **including `$D000–$DFFF`**. At `$35` those addresses are VIC/SID/CIA, not enemy DRAM. |
| 59 | `$EECD`–`$EEFF` | ~51 B free before map. |
| 59–63 | `$EF00`–`$FEFF` | **`MAP`** 4K (disk `e1mN`; under-KERNAL). |
| 63 | `$FF00`–`$FFFF` | `$FF00`–`$FFF9` unused. Hardware vectors `$FFFA`–`$FFFF` (`nmi_stub` / `input_irq`) when ROM is out. |

---

## Major regions (summary)

| Range | Role |
|-------|------|
| `$0002`–`$00FF` | Zero page (`zp.asm`). `$90`–`$A4` reserved for KERNAL IEC. Skip `$AE–$AF`, `$B7–$BC` across in-play LOAD. |
| `$0100`–`$01CF` | Under-stack BSS (`vis_slot` / `vis_perp_*` / `enemy_burst`). `STACK_GUARD` `$01D0`–`$01FF`. |
| `$033C`–`$03EB` | Cassette BSS (player/doors/AI scratch; not in locode PRG). Limit `$03FC`. |
| `$0400`–`$07D2` | Render tables (`tab`) |
| `$0801`–`$08A9` | Low BSS overlay (was boot) |
| `$08C0` | `REBOOT_STUB` |
| `$08FD`–`$08FF` | Menu selectors |
| `$0900`–`$26A0` | Locode (game code; no enemy modules; must stay `< $3000`) |
| `$26A1`–`$2FFF` | Free (runtime). MENU used this up to `$3633` before locode loaded. |
| `$3000`–`$345E` | PC SFX |
| `$345F`–`$37FF` | Slack after SFX to SQTAB |
| `$3800`–`$3FFF` | Judd SQTAB1–4 |
| `$4000`–`$47E7` | VIC matrices A/B |
| `$4800`–`$4A85` | BJ-head HUD sprites (10×64 + tables) |
| `$4A86`–`$4DFF` | Slack after BJH / menu sprites |
| `$4E00`–`$4EEB` | Krill resident on **`wolf64-krill.d64`** only (`loadraw`) |
| `$4EEC`–`$4FFF` | Reserved tail of the hole |
| `$5000`–`$587F` | Weapon HUD sprites |
| `$5880`–`$5FFF` | Item gfx + `col_enemy` |
| `$6000`–`$7F3F` | VIC bitmap (score code in UI tail `$64B0`) |
| `$8000`–`$8FFF` | `TEX_LO` |
| `$9000`–`$9FFF` | `TEX_HI` (derived, RAM-only) |
| `$A000`–`$BC91` | Wall painters. Boot first stages ENEMY here. |
| `$BC92`–`$BF09` | `col_wallz_h` + item/vis + cold enemy SoA |
| `$C000`–`$EECC` | Enemy block (under-I/O included) |
| `$EF00`–`$FEFF` | Level map |

---

## Boot / menu overlays (not the play map)

| When | `$0900` | `$2000` | `$3800` | `$4000` | `$4800` | `$6000` | `$A000` |
|------|---------|---------|---------|---------|---------|---------|---------|
| Splash | boot `$0801` | Krill `install` (then free) | free | splashc matrix + helpers | helpers may reach here | splash bitmap | free |
| Menu | `menu.prg` `$0900`–`$3633` | **inside MENU** | menufont | hires matrix | logo/hint/cursor sprites | hires bitmap | — |
| After copy_enemy, before locode | still MENU | — | menufont | still splash/menu bitmap | sprites | cover | ENEMY staging |
| Play | locode | locode (if `end_locode` grows, limit `$3000`) | `sqt` | `scr` | `bjh` | `bmp` | `paint` |

---

## Disk files

Write order on `wolf64.d64` is boot, splashc, splash, menu, then slices + maps. Runtime load order is the boot sequence above, then `e1mN` from locode.

| DOS name | PRG / slice | Load | Size (this build) |
|----------|-------------|------|-------------------|
| `wolf64` | `generated/boot.prg` | `$0801` | 240 B; must end ≤ `$08FC` |
| `loader` | `krill/loader.prg` | `$4E00` | Krill disk only (~236 B) |
| `install` | `krill/install.prg` | `$2000` | Krill disk only (transient; MENU overwrites) |
| `splashc` | `generated/splashc.prg` | `$4000` | matrix + colour staging + `do_splash` |
| `splash` | `generated/splash.prg` | `$6000` | 8000-byte MCM bitmap |
| `menu` | `generated/menu.prg` | `$0900` | ~11571 B; must end before `$4000` |
| `enemy` | slice of `game_image.prg` | `$A000` → copy `$C000` | PRG header `$A000`; destination is staging |
| `locode` | slice | `$0900` | `$0900`–`$26A0` |
| `scr` | slice | `$4000` | `$4000`–`$47E7` |
| `sfx` | slice | `$3000` | `$3000`–`$345E` |
| `bjh` | slice | `$4800` | `$4800`–`$4A85` |
| `wpn` | slice | `$5000` | `$5000`–`$587F` |
| `itm` | slice | `$5880` | `$5880`–`$5FD7` |
| `bmp` | slice | `$6000` | through `end_bmp` `$7FC0` |
| `sqt` | `generated/sqtab.prg` | `$3800` | 2048 B |
| `texlo` | slice | `$8000` | 4096 B |
| `paint` | slice | `$A000` | `$A000`–`$BC91` |
| `tab` | slice | `$0400` | `$0400`–`$07D2` |
| `col` | `colorram.bin` | `$D800` | 1000 B colour RAM |
| `e1m1`…`e1ms` | `maps/*.bin` | `$EF00` | 4096 B each |

`TEX_HI` is not on disk.

---

## Low BSS overlay (`$0801`, after boot)

Not emitted into locode. `game_start` does not clear this block (column buffers are written every frame).

| Addr | Size | Symbol |
|------|--------|--------|
| `$0801` | 40 | `col_texid` |
| `$0829` | 40 | `col_half_h` |
| `$0851` | 40 | `col_texx` |
| `$0879` | 40 | `col_wallz_l` |
| `$08A1` | 1 | `load_namelen` |
| `$08A2` | 2 | `load_name_l` / `load_name_h` |
| `$08A4` | 1 | `load_do_pad` |
| `$08A5` | 1 | `load_jiffy0` |
| `$08A6` | 1 | `episode` |
| `$08A7` | 1 | `level_num` |
| `$08A8` | 1 | `secret_from` |
| `$08A9` | 1 | `load_in_play` |
| `$08AA` | — | `end_bss` (must be ≤ `REBOOT_STUB`) |

---

## Cassette-buffer BSS (`$033C`–`$03EB`)

Locode runtime; zero-filled once in `game_start`. Disk `LOAD` does not use the tape buffer. Limit `TAPE_BSS_END` `$03FC`.

Player, doors (8 slots), enemy-draw scratch, `turn_acc`, mouse/frame/score, BJ look cadence. `end_tape_bss` = `$03EC` this build (~176 B).

---

## Under-stack BSS (`$0100`–`$01CF`)

| Addr | Size | Symbol |
|------|------|--------|
| `$0100` | 48 | `vis_slot` |
| `$0130` | 48 | `vis_perp_l` |
| `$0160` | 48 | `vis_perp_h` |
| `$0190` | 64 | `enemy_burst` |
| `$01D0` | 48 | `STACK_GUARD` — IRQ + nested `jsr`. Do not let `SP` drop below `$D0`. |

---

## After painters (`$BC92`–`$BFFF`)

| Addr | Size | Symbol |
|------|------|--------|
| `$BC92` | 40 | `col_wallz_h` |
| `$BCBA` | 48 | `item_x` |
| `$BCEA` | 48 | `item_y` |
| `$BD1A` | 48 | `item_frm` |
| `$BD4A` | 48 | `vis_depth_l` |
| `$BD7A` | 48 | `vis_depth_h` |
| `$BDAA` | 48 | `vis_order` |
| `$BDDA` | 48 | `vis_kind` |
| `$BE0A` | 64 | `enemy_state_t` |
| `$BE4A` | 64 | `enemy_type` |
| `$BE8A` | 64 | `enemy_hp` |
| `$BECA` | 64 | `enemy_state` |
| `$BF0A` | — | `end_item_soa` (~246 B free to `$C000`) |

`col_enemy` is 40 bytes at `$5FD8` (itm→bitmap slack), not in this gap.

Hot enemy pos/facing/flags are at the tail of the enemy PRG (`enemy_xh`…`enemy_flags`, 6×64).

---

## VIC graphics (bank 1, play)

`$DD00` bits 0–1 = `%10` → `$4000–$7FFF`. `$d018` `%00001000` / `%00011000` (matrix A/B, bitmap `$6000`). Re-apply after KERNAL LOAD.

| Resource | Address |
|----------|---------|
| Matrix A / B | `$4000` / `$4400` |
| Sprite pointers | `$43F8` / `$47F8` (while that matrix is shown) |
| BJ-head HUD sprites | `$4800`–`$4A85` (10×64 + ptr tables, VIC ptrs `$20`–`$29`; raster-muxed with weapons) |
| Weapon sprites | `$5000`–`$587F` (VIC index from `$4000`) |
| Weapon mux snapshot | locode `wpn_snap_ptr` / `_col` / `_xy`; raster 88 blits to VIC |
| Item gfx | `$5880` (CPU; not VIC sprite pointers) |
| Bitmap | `$6000`–`$7F3F` |
| Colour RAM | `$D800`–`$DBE7` (I/O in only) |

Painters write the **back** matrix via ZP `view_row0..23`. `swap_view` flips `$d018` inside a `$35` window.

---

## `$01` (play)

| Value | Use |
|-------|--------|
| `$34` | Default play / render (enemy DRAM at `$D000` visible as RAM) |
| `$35` | Chip touch: VIC, SID, CIA, colour RAM; IRQ/NMI |
| `$36` | KERNAL LOAD (BASIC out so `$A000` painters stay RAM) |

See [TechNotes.md](TechNotes.md) § `$01` banking.

IRQ/NMI save `$01`, set `$35`, ack, restore. Hardware vectors `$FFFE` / `$FFFA` (KERNAL out). Play IRQ is CIA1 Timer A (input/SFX) plus VIC raster mux (HUD faces at raster 40, weapons at 88). In-play `LoadLevel` `IOINIT`s and must re-run `init_vic` / `input_irq_init` / `play_sound_init`.

---

## Free scrap (this build)

| Range | Bytes | Notes |
|-------|------|--------|
| `$07D3`–`$0800` | 46 | After tables |
| `$26A1`–`$2FFF` | ~2399 | After locode, before SFX |
| `$345F`–`$37FF` | ~929 | After SFX, before SQTAB |
| `$4A86`–`$4DFF` | ~378 | After BJH; growth room before Krill hole |
| `$4E00`–`$4FFF` | 512 | Reserved (`loadraw` on Krill disk) |
| `$7FC0`–`$7FFF` | 64 | Bitmap tail after hexfont |
| `$BF0A`–`$BFFF` | 246 | After item/vis SoA |
| `$EECD`–`$EEFF` | 51 | After enemy, before map |
| `$FF00`–`$FFF9` | 250 | Above map; keep vectors `$FFFA`–`$FFFF` |

Assemble overlap errors: locode vs `SFX_BASE`, SFX vs `SQTAB1`, BJH vs `KRILL_HOLE`, painters+SoA vs `ENEMY_BASE`, enemy vs `MAP`, tape BSS vs `$03FC`, stack BSS vs `$01D0`. Locode/enemy free bytes are ACME `!warn` at assemble.

Sources: `wolf64.asm`, `mem.asm`, `zp.asm`, `boot.asm`, `menu.asm`, `loader.asm`, `vic.asm`, `generated/wolf64.lbl`.
