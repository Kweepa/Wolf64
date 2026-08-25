# Tech notes

## Wall textures MUST come from walls_preview.png, not raw VSWAP

`tools/extract_walls.py` has two source modes:

- **bare (no flags)** — pulls straight from `shareware/VSWAP.WL1`. This is
  **only** for the very first bootstrap of `textures/walls_preview.png`.
- **`--from-preview`** — rebuilds from the checked-in, **hand-edited**
  `textures/walls_preview.png` (see its git log: "Updated purple stone
  textures", "Updating some textures" — real hand tuning, not just an
  extraction artifact).

**Always use `--from-preview` for any real rebuild.** Running the bare mode
after `walls_preview.png` has been hand-edited silently discards that
editing — verified 2026: regenerating bare produced a `tex_lo.bin` where
**1518 of 4096 texels (37%)** differed from the checked-in-history
`walls.bin`, which looked like a rendering bug (some screen columns "right",
some "wrong") until a VICE snapshot diff proved `col_texid`/`col_half_h`/
`col_texx` were byte-identical between the old and new build — i.e. the
*raycasting* was correct and only the *texture data itself* had drifted.
`--from-preview` reproduces the old `walls.bin` bit-exactly (0/4096 diff).

If you ever see "some columns/textures look wrong but the geometry seems
right" again, diff the actual texel data against source control history
before suspecting the renderer — see `tools/extract_walls.py`'s
`build_slots_from_vswap` vs `extract_from_preview`.

## Wall-paint dispatch & painter_near micro-optimizations (2026-08-21)

### Height dispatch: one `.word` jump table, one patched byte

`painter_tbl` (`generated/src/painters.asm`, via `tools/gen_painters.py`) is a
single `.word` table — height (1..75, plus an unused index 0) → `painter_hNN`
address — emitted **first**, so it lands exactly on `PAINTERS` ($A000, already
page-aligned by the memory map). Because every entry then shares the same
high byte, `paint_column`'s dispatch (`render.asm`) only ever patches **one**
byte: the low byte of an indirect `jmp (painter_tbl)`'s operand (`.pj+1 =
half_h*2`). The high byte is baked in at assembly time and never touched.

Why not the old fixed `jmp $nnnn` with two patched bytes (`painter_lo`/
`painter_hi` byte tables + two `sta`s)? Same effect, but this halves the
runtime writes, and since offsets are always even (`2*half_h`), the vector's
low byte can never be `$ff` — so the classic 6502 JMP-indirect page-wrap bug
(`JMP ($xxFF)` reads its high byte from `$xx00` instead of the next page)
can't bite, with no extra alignment padding needed (`PAINTERS` was already
page-aligned for other reasons).

### `col_texx` stored pre-shifted

`X = texx*16+id` used to cost a shift on **both** ends: `dda.asm`/`doors.asm`
reduced the raw 8-bit U coordinate to `texx` (0..15) via `lsr`×4, and
`paint_column` then shifted it back left via `asl`×4 to reposition it before
ORing in `tex_id`. Since `col_texx`'s only consumer is that one X-register
combine, there's no reason to store it in the 0..15 "natural" range at all —
`dda.asm hit_wall` / `doors.asm door_try_x`/`door_try_y` now do `and #$f0`
instead of `lsr`×4, storing it already positioned in the high nibble.
`paint_column` just does `ora` directly. Net: both shifts gone, for free
(`and #$f0` costs exactly what the `lsr`×4 it replaced cost).

### `paint_column`: one `Y` load, no `tmp3`, sky/floor inlined

- `Y = col` loads once at entry and is never reloaded — not by the painter
  dispatch, not by the sky/floor miss path — nothing in between touches `Y`.
- `tmp3` (used to stash `tex_id` across the `half_h` clamp) is gone:
  `col_texx,y` ORs directly into `tex_id` (still in `A` right after the
  `col_texid,y` load) and `tax`'s immediately, before the clamp's own
  `A`-clobbering logic runs.
- `draw_sky_floor` had exactly one caller and was short, so it's inlined
  under the `bpl .have_tex` check instead of `jmp`'d to. The common
  (wall-hit) path already paid for a branch either way; the miss path no
  longer *also* pays for a `jmp` on top of it.
- The redundant `lda half_h` right after `sta half_h` was dropped (`A`
  already holds that value; `sta` doesn't touch `A`). `half_h` itself stays
  a real store, though — `painter_near` (heights 51..75) reads it back
  repeatedly, both to seed its Bresenham state and inside its per-cell loop.

### `painter_near` setup: `near_tex0` table replaced by a 2-way branch

`near_tex0[h]` (starting texture row for the Bresenham near-loop, h=51..75)
turned out to only ever take **two** distinct values: 4 for h=51..53, 5 for
h=54..75 (`tex0 = floor((8h-160)/h)`, crosses from 4 to 5 exactly at h=54).
A 25-entry table plus a runtime `adc` is overkill for one transition point.
Replaced with a build-time-constant branch using the classic "skip via
`BIT`-absolute" idiom:

```
	cpy #3
	bcc +
	lda #(>TEX_LO)+5
	!byte $2c		; turns the skipped lda into a harmless BIT $nnnn operand
+	lda #(>TEX_LO)+4
	sta .pn_ld2+2
```

`!byte $2c` (the `BIT $nnnn` opcode) turns the *skipped* `lda`'s own
opcode+operand bytes into a harmless `BIT $nnnn` (reads memory for flags
only, never touches `A`), so the branch-taken and fallthrough paths converge
without needing a `jmp`.

`TEX_HI`'s equivalent constant is derived from the `TEX_LO` one with a
single `eor #(>TEX_LO) XOR (>TEX_HI)` instead of a second `cpy`/`bcc` block —
valid because `TEX_HI = TEX_LO + 4096` exactly (both page-aligned, so their
high bytes differ in exactly one bit, `$10`) and `tex0 < 16` never carries
into that bit, so XOR and the original `+4`/`+5` addition agree on both
operands. `near_err0` (the Bresenham error seed) stays a real table — unlike
`near_tex0` it has no closed form cheap enough to beat one indexed load.

**Caution for future edits: `^` is not XOR in ACME.** It silently parsed as
something else while building this (produced `$00` instead of `$10` — check
with a scratch `!byte A^B` vs `!byte A XOR B` build if unsure). The working
keyword is `XOR` (`EOR` also works but is deprecated).

### `painter_near` loop: one unconditional `clc` per iteration, not three

The per-cell loop did `clc` before all three `adc`s (top-row step,
bottom-row step, screen-pointer advance). Only the first is unavoidable
(carry out of the *previous* iteration's pointer-advance isn't predictable).
For the other two: when the preceding `bcc .pn_s1`/`.pn_s2` is **taken**,
carry is already 0 (that's the branch condition), and nothing between the
branch target and the next `adc` (`lda`/`ora`/`sta` — none of which touch
`C`) changes it — that path never needed a `clc`. The **not-taken**
(`sbc`+`inc`+`inc`, row-advance) arm now ends with its own `clc` so both
arms reach the next `adc` with `C=0` either way. Net: same instruction count
(2 `clc`s moved from the always-executed convergence points onto the
row-advance-only arm), but the common case — most cells, most columns, no
row advance — is 2 instructions/4 cycles shorter per iteration. Pure runtime
win, zero code-size change.

All of the above verified against the real ACME build plus direct
machine-code byte inspection of `generated/game_image.prg` (not just the
generated `.asm` text) — two of the tricks above (the `+4`/`+5` placement in
the skip-trick, and the `^`-vs-`XOR` mixup) were genuinely wrong on the
first pass and were only caught this way.

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

Boot PRG (`wolf64` on `wolf64.d64`) lives at `$0801`. It loads **MENU** at
`$0900`, `JSR`s it (difficulty → `$08FF`; shareware always episode 0), then stages
**ENEMY** and calls MENU`+3` (`copy_enemy`), then loads remaining assets with
plain KERNAL SETNAM/SETLFS/LOAD (clear `$90`/ST between files; no per-file
IOINIT/CIA). **LOCODE** overwrites the menu at `$0900`. Boot then jumps to
`LOCODE_BASE`:

| DOS | Load | Contents |
|-----|------|----------|
| `menu` | `$0900` | title/menu overlay (text mode + menufont @ `$3800`; disposable) |
| `enemy` | `$9000`→`$C000` | enemy block (staged at `PAINTERS`, then copied) |
| `locode` | `$0900` | game code (no enemy modules; replaces menu) |
| `scr` | `$4000` | video matrices |
| `sfx` | `$4800` | PC sounds + freq (old walls.bin slot; ends `$4C5F`, `WPN_SPRITES` at `$5000`) |
| `wpn` | `$5000` | weapon HUD sprites (all 4 + flashes, ends `$5880`) |
| `itm` | `$5880` | world item gfx (4bpp frames + LUTs, to `$6000`) |
| `bmp` | `$6000` | MCM bitmap |
| `sqt` | `$3800` | Judd square tables (2K; replaces menufont) |
| `texlo` | `$8000` | `TEX_LO` — row×256+texx×16+id, one texel/byte, pre-masked (4K) |
| `paint` | `$A000` | wall height painters |
| `tab` | `$0400` | `tables.asm` (DEN blank — not visible) |
| `col` | `$D800` | colour RAM |

`TEX_HI` (also `$9000`-style row×256+texx×16+id layout, hi nibble pre-masked)
is **not** a disk file: `init_tex_hi` (`render.asm`, called once from
`game_start`) builds it in RAM at `TEX_HI = end_paint` ($AC13) by shifting
every `TEX_LO` byte left 4 bits — the two tables hold the same information,
so shipping/loading a second 4 KB blob would be pure waste.

Locode’s `LoadLevel` pulls `e1m1` into **`$EF00`**. After handoff, **low BSS
overlays the boot footprint** (`$0801`…`$08BF`). **`$08C0`** holds a 3-byte
`JMP reboot_game` trampoline installed by `locode_entry` (`reboot_game` lives
in the enemy block so locode stays under SQTAB); **game over** (lives expired)
blacks the screen and jumps there to LOAD `wolf64` and re-enter the menu.
Deaths with lives remaining set `level_want=1` and restart the level. **`$08FF`**
is `difficulty`. After `end_paint`: `TEX_HI` (RAM-only, see above), then
`col_wallz_h` / `col_enemy` (the latter in the itm→bitmap slack), then
item/vis/cold-enemy SoA → `<$C000`. There is no more painter SMC and no
`ph_h_done` — heights 1..75 all address `TEX_LO`/`TEX_HI` directly via
`X = texx*16+id`, set once per column in `paint_column`.

`LoadPrg` / `LoadLevel` stay resident in locode for **in-play level advance**
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

### Cassette-buffer BSS (`$033C–$03FB`)

Locode runtime BSS (player/doors/AI scratch, `turn_acc`, frame timing) lives in the
**cassette buffer** — not emitted into the locode PRG. Disk `LOAD` does not use
this region. `game_start` zero-fills `TAPE_BSS`‥`end_tape_bss` once. ~170 bytes
today; limit `TAPE_BSS_END` (`$03FC`). `PROFILE=1` extras stay in the locode image.

### Under-stack BSS (`$0100–$01CF`)

Hardware stack grows down from `$01FF`. Reserve **`$01D0–$01FF`** (`STACK_GUARD`) for
IRQ + nested `jsr` (48 bytes); put cold/runtime tables in `$0100..STACK_GUARD`:

| Symbol | Size | Role |
|--------|------|------|
| `vis_slot` | 48 | per-frame depth draw list |
| `enemy_burst` | 32 | shots left in volley (dogs: repath countdown) |
| `enemy_state_t` | 32 | state timers |
| `enemy_anim_t` | 32 | walk-phase ms |
| `enemy_view` | 32 | billboard octant |
| `enemy_type` | 32 | spawn type (cold; not in enemy PRG) |

Ends at `$01D0` today (`end_stack_bss`). Not part of any disk PRG. Do not let `SP`
drop below `$D0`.

### Under-I/O RAM (`$D000–$DFFF`)

4K free for gameplay data under the default `$34` map. Opaque during the brief
`$35` windows above (and during the IRQ). Prefer cold / staging data over
hot per-frame tables that an IRQ might need.

## Screen double-buffer (`$4000` / `$4400`)

Painters write colour nibbles straight into the **back** video matrix via ZP `view_row0..23` (`sta (view_rowN),y`, Y=column). `init_vic` / level restart call `set_view_rows` once (`view_row0` → matrix row 3 so cells 2..21 land on screen rows 5..24). After paint, `swap_view` flips `$d018` between `%00001000` (matrix `$4000`) and `%00011000` (matrix `$4400`) inside a `$35` window, then `eor #$04` on the 24 `view_row*` **high** bytes (`SCREEN` vs `SCREEN_B`). Shared multicolour bitmap at `$6000` is not flipped. No transposed FRAMEBUF / blit pass.

## Profiler HUD (SquareDoom CIA2 cascade)

`PROFILE=1` / `DBG_FPS=1` in `src/wolf64.asm`. CIA2 TA/TB cascaded ϕ2 clock (`src/profil.asm`). Bitmap row 0 shows approx **ms** (same `(cycles>>8)>>2` as SquareDoom).

**`PROFILE=1` does not fit locode** (BSS + gated bodies push `end_locode` past SQTAB `$3800`). Ship with **`DBG_FPS=1`** (cols 0–2 = **F** only). Do not move Judd tables to make the full HUD fit. `PROF_SPLIT=1` is extra code and ~20ms of CIA samples — leave off.

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

## DDA / paint / sprites (speed)

Per frame: `setup_player_tile` → cast cols 1..38 → paint 1..38 → `enemies_draw` → `swap_view`. Cast cannot split setup×38 then march×38: tile-pointer SMC is per-column.

**March (`cast_march`).** `Y=0` for `lda (tile_l),y` for the whole ray. `door_try_x` / `door_try_y` restore `Y=0` on the continue (pass) path. X-grid miss loops with `dex / bne .inner`; Y-grid miss is `dex / beq .miss / jmp .inner` (relative branch too far). If `xstep`/`ystep` match the previous column (`dda_last_x/y`, ZP `$c6/$c7`; 0 = none), skip the six INC/DEC / ADC/SBC opcode patches. Same door cell: `door_cell_get` caches orient+pos (`door_cx` `$ff` in `setup_player_tile`); closed-door fill is one slot/infer per frame. Infer peeks N/S as `tile_* ± 64`. `calc_half_h` uses `heightab[wallz>>5]` including idx 0 (75) — no `$1800/z` subtract for `wallz < 32`.

**Map.** `map_to_tile`: `tile = map_row[mapy] + mapx`. `map_row_lo/hi` in `tab` (`MAP + y*64`, 64×64).

**Wall paint.** No painter SMC of any kind beyond a single patched byte (see below). `X = texx*16+id` is built once per column in `paint_column` (`render.asm`) and never touched again — same register value feeds every height, 1..75. `TEX_LO`/`TEX_HI` hold every `(row, texx, id)` texel pre-masked at build time (`tools/extract_walls.py`): `TEX_HI + row*256,x` = texel in the high nibble (low nibble already 0), `TEX_LO + row*256,x` = texel in the low nibble (high nibble already 0). Heights 1..50 (compile-time row) just emit `lda TEX_HI+row_top*256,x` / `ora TEX_LO+row_bot*256,x` per cell — no `AND`, no shift, no table lookup. Heights 51..75 (`painter_near`, runtime Bresenham row) start each of its two `LDA` sites' high-byte operand at a build-time `TEX_HI`/`TEX_LO`-relative constant and `inc` it by one page whenever the Bresenham error carries — `X` still never changes through the whole loop. Solid sky/floor cells are `lda #$bb/#$cc` runs; horizon blends `ora` directly against the sky/floor immediate, no intermediate `tmp0` needed there. Full rationale for the dispatch table, the `col_texx` pre-shift, and the `painter_near` setup/loop tricks: see "Wall-paint dispatch & painter_near micro-optimizations" below.

**Hit.** `hit_wall` loads `aux` from `sdx` or `sdy` once (U `fixcos` mul then fish `fishtab[col]`); one `ldx col` for the column stores.

**Sprites.** `enemy_calc_spr_h` = `(3/2)*half_h` clamped to `ENEMY_MAX_H` (48). Draw path: one `e_dx` = sprite−player, `enemy_side_from_delta`, FOV cull, then `project_col_from_side` (16/8 or 8/8 `div_q40` in `items_draw.asm`; no per-pixel subtract-up-to-40). Off-screen sprites skip `atan2` / `pick_frm`. `neg_e_delta` then `enemy_atan2` for octant. `enemy_paint_col` splits even/odd rows with `lsr / bcs`; `e_hitscan` patched once per column. After depth, `vis_compact_behind` drops `$ffff` (behind camera) before sort; `enemy_sort_depth` skipped when `vis_count < 2`. Item AABB (`items_cull_near`) walks `tile_*` +1 / +64 after one `map_to_tile`.

## VICE snapshot dump (`tools/vsf_dump.py`)

When the emulator hangs or crashes, save a VICE snapshot (`.vsf`) and dump it against the labels from **that same build**:

```
python tools\vsf_dump.py vice-snapshot-YYYYMMDDHHMMSS.vsf wolf64.lbl
```

Prints module list, `PC` / `A` / `X` / `Y` / `SP` / `P` with the nearest ACME label, `$01`, bytes around `PC`, stack words that look like `jsr` returns (also label-resolved), and ZP `$00–$7F`.

The hang is often still “running” (IRQs alive, code bytes match the image). Use `PC` + the return chain to see which `jsr` never came back; SoA / BSS dumps from the extracted RAM are a follow-up, not part of this script. `MAINC64CPU` is x64sc; older VICE used `MAINCPU`.
