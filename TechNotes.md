# Tech notes

## `$01` banking

### PLA table

Low 3 bits of `$01` are LORAM / HIRAM / CHAREN (bits 0/1/2). With no cartridge:

| `$01` | `$A000–$BFFF` | `$D000–$DFFF` | `$E000–$FFFF` |
|-------|---------------|---------------|----------------|
| `$37` | BASIC ROM     | I/O           | KERNAL ROM     |
| `$36` | RAM           | I/O           | KERNAL ROM     |
| `$35` | RAM           | **I/O**       | RAM            |
| `$34` | RAM           | **RAM**       | RAM            |

BASIC ROM only appears when LORAM **and** HIRAM are both set. `$35` and `$34`
both bank out BASIC and KERNAL; the difference is whether `$D000–$DFFF` is
I/O or RAM.

### The rule

**Default is `$01 = $34`** (I/O out). `$A000–$FFFF` is all plain RAM during
gameplay and render. VIC ignores `$01` for its own fetches, so the bitmap /
matrices / sprites keep displaying.

I/O is banked in (`$01 = $35`) only when chips must be touched:

1. **Warmstart** — stays `$35` for VIC / SID / CIA init, then flips to `$34`
   before `cli`.
2. **IRQ / NMI** — save `$01`, set `$35`, do keyboard + SID (or NMI ack),
   restore `$01`.
3. **Brief main-loop windows:**
   - `prof_read_casc` — CIA2 timer reads (save/restore)
   - `swap_view` — `$d018` flip
   - `update_weapon` — sprite registers `$d000–$d02x`
   - `prof_print` — colour RAM `$d800` digit colour

`play_sound` is **queue-only** (RAM); the Timer A IRQ's `update_sfx` does all
SID writes, so gameplay callers never need a `$35` window for audio.

`$36` is used for KERNAL disk loads — see below.

### Disk loading

Boot PRG (`wolf64` on `wolf64.d64`) lives at `$0801`, blanks DEN, and loads
**all assets except the map** with plain KERNAL SETNAM/SETLFS/LOAD (clear `$90`/ST
between files; no per-file IOINIT/CIA), then jumps to `LOCODE_BASE` (`$0900`):

| DOS | Load | Contents |
|-----|------|----------|
| `locode` | `$0900` | game code (no enemy modules) |
| `tex` | `$4800` | wall textures |
| `wpn` | `$5000` | weapon HUD sprites (all 4 + flashes, ends `$5880`) |
| `sqt` | `$3800` | Judd square tables (2K, locode–screen gap) |
| `paint` | `$8000` | wall height painters |
| `sfx` | `$B8F2` | PC sounds + freq |
| `enemy` | `$C000` | enemy code, AI, helpers, pixels, SoA |
| `tab` | `$0400` | `tables.asm` (DEN blank — not visible) |

Locode’s `LoadLevel` pulls `e1m1` into **`$EF00`**. Judd SQTAB is filled after
loads at `$3800–$3FFF`. `$5880–$5FFF` is reserved for item HUD sprites.
After handoff, **low BSS overlays the boot footprint** (`$0801`…`$08FF`).

`LoadPrg` / `LoadLevel` stay resident in locode for **restart** (`restart_level`)
without reloading code or assets. Future overflow code may ship as `hicode`.

To load from disk with the KERNAL:

1. Set `$01 = $36` — KERNAL + I/O in, **BASIC stays out** so painters remain
   readable during the load.
2. With KERNAL in, hardware IRQs route through ROM to the soft vector: point
   `$0314/$0315` at a stub (ack CIA1, `rti`) or disable the CIA1 Timer A IRQ
   for the duration. `LoadPrg` RESTOR/IOINIT then re-inits game IRQs on exit.
3. KERNAL uses ZP `$90–$FF` heavily — `LoadPrg` clears `$90–$98`; in-play loads
   must save any survivors in that range (weapon/input ZP today).
4. Writes go through ROM to RAM, so loading into `$E000+` works even with
   KERNAL banked in. **Never load directly into `$D000–$DFFF`** while I/O is
   in — stage elsewhere and copy under `$34`.
5. Restore `$01 = $34` (gameplay default) after init; `LoadPrg` leaves `$35`
   briefly for VIC/CIA restore then callers continue.

Map is disk-only at `$EF00` (not part of the locode image).

### Under-I/O RAM (`$D000–$DFFF`)

4K free for gameplay data under the default `$34` map. Opaque during the brief
`$35` windows above (and during the IRQ). Prefer cold / staging data over
hot per-frame tables that an IRQ might need.

## Screen double-buffer (`$4000` / `$4400`)

Painters write colour nibbles straight into the **back** video matrix via ZP `view_row0..23` (`sta (view_rowN),y`, Y=column). After paint, `swap_view` flips `$d018` between `%00001000` (matrix `$4000`) and `%00011000` (matrix `$4400`) inside a `$35` window. Shared multicolour bitmap at `$6000` is not flipped. No transposed FRAMEBUF / blit pass.

## Profiler HUD (SquareDoom CIA2 cascade)

`PROFILE=1` / `DBG_FPS=1` in `src/wolf64.asm`. CIA2 TA/TB cascaded ϕ2 clock (`src/profil.asm`). Bitmap row 0 shows approx **ms** (same `(cycles>>8)>>2` as SquareDoom):

Pipelined render stores per-column `col_texid` / `col_half_h` / `col_texx`, then paints the back matrix.
Default **`PROF_SPLIT=0`**: stage-boundary buckets only.  
**`PROF_SPLIT=1`**: per-column **R**/**D** (~80 samples; adds ~20ms to **F** — useful for ratio, not absolute frame cost).  
`setup_player_tile` is folded into **C** / first **R** (sub-ms; not shown).  
**U** = `enemies_update`; **O** = `enemies_draw` (paint sample excludes objects; CIA read sits between paint and draw).

| Cols | `PROF_SPLIT=0` | `PROF_SPLIT=1` |
|------|----------------|----------------|
| 0–2 | **F** frame | **F** |
| 4–6 | **C** cast×40 | **R** ray setup×40 |
| 8–10 | **P** paint | **D** march+hit×40 |
| 12–14 | **U** obj update | **P** |
| 16–18 | **O** obj draw | **U** |
| 20–22 | **L** LOS grant | **O** |
| 24–26 | — | **L** |

**L** times the single `enemy_los_rr` grant (`check_sight` / chase LOS / `enemy_shoot`) via nested CIA sample — also counted inside **U**.

HUD screen nibbles go to the **front** matrix (`set_scr_front` after `swap_view`). CIA2 reads and `$d800` colour writes go through `$35` windows (`prof_read_casc` / `prof_print`). Does not touch `$dd00` (VIC bank).
