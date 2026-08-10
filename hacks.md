# Hacks / workarounds

## `$01` banking (temporary — not the intended map)

### Intended end state (not done)

**Game code and data live in full RAM:** BASIC, KERNAL, and I/O all banked out so `$A000–$FFFF` (under-BASIC, under-I/O, under-KERNAL) is ordinary usable memory. Nothing in the main loop should need a `$01` flip to fetch painters or touch game data.

**Only the IRQ** banks I/O in (briefly) to read the keyboard CIA and, later, to drive audio — then banks out again. That is the *only* planned dance.

Under-I/O (`$D000–$DFFF`) and under-KERNAL (`$E000–$FFFF`) are therefore **free real estate**, not “awkward shadow RAM.” Treat them as available once the permanent all-RAM map works.

### What the code does now (hack)

(`src/dda.asm` `render_frame`, `src/wolf64.asm` `start`)

- Stay on **`$35`** (BASIC in, KERNAL out, I/O in) for init, main loop, `$d018` swap, profiler CIA reads.
- Enter **`$34`** (BASIC out, KERNAL out, I/O in per the usual PLA table) only for column/painter/SMC work inside `render_frame`, then restore **`$35`**.

**Why the flip exists today:** Compiled painters extend through `$A000–$BFFF`. With `$35` the CPU fetches **BASIC ROM** there; `$34` exposes the painter **RAM**. This is a crutch so painters can sit under the BASIC window without a working all-RAM `$01`.

### Why permanent all-RAM failed (unresolved)

**Symptom:** With `$01 = $34` left on for the whole run, the bitmap still updated (walls looked correct) but VIC/CIA traffic died — border colour stuck, WASD via `$dc00`/`$dc01` did nothing. Switching back to `$35` for the main loop restored border + keyboard.

**Why this is still a hack:** On the standard PLA map, `$34` and `$35` both leave I/O at `$D000–$DFFF` (CHAREN=1). Permanent `$34` (or a true all-RAM mode with I/O out except in IRQ) *should* be enough for painters + game RAM; VIC/CIA would only need I/O during the IRQ. Empirically, leaving `$34` on killed I/O access from the main loop. Root cause unresolved — possibly VICE/config interaction, uncleared CIA state under `sei`, wrong `$01` value for “RAM everywhere + I/O when we want it,” or something else not pinned down.

**Do not “fix” this by inventing more main-loop bank flips.** Fix the permanent map so the IRQ owns I/O and the rest of `$A000–$FFFF` stays RAM.

## Screen double-buffer (`$4000` / `$4400`)

Painters write colour nibbles straight into the **back** video matrix via ZP `view_row0..23` (`sta (view_rowN),y`, Y=column). After paint, `swap_view` flips `$d018` between `%00001000` (matrix `$4000`) and `%00011000` (matrix `$4400`). Shared multicolour bitmap at `$6000` is not flipped. No transposed FRAMEBUF / blit pass.

## Profiler HUD (SquareDoom CIA2 cascade)

`PROFILE=1` / `DBG_FPS=1` in `src/wolf64.asm`. CIA2 TA/TB cascaded ϕ2 clock (`src/profil.asm`). Bitmap row 0 shows approx **ms** (same `(cycles>>8)>>2` as SquareDoom):

Pipelined render stores per-column `col_texid` / `col_half_h` / `col_texx`, then paints the back matrix.
Default **`PROF_SPLIT=0`**: stage-boundary buckets only.  
**`PROF_SPLIT=1`**: per-column **R**/**D** (~80 samples; adds ~20ms to **F** — useful for ratio, not absolute frame cost).  
`setup_player_tile` is folded into **C** / first **R** (sub-ms; not shown).  
**U** = `enemies_update`; **O** = `enemies_draw` (paint sample excludes objects; brief `$01=$35` between paint and draw for the CIA read).

| Cols | `PROF_SPLIT=0` | `PROF_SPLIT=1` |
|------|----------------|----------------|
| 0–2 | **F** frame | **F** |
| 4–6 | **C** cast×40 | **R** ray setup×40 |
| 8–10 | **P** paint | **D** march+hit×40 |
| 12–14 | **U** obj update | **P** |
| 16–18 | **O** obj draw | **U** |
| 20–22 | — | **O** |

HUD screen nibbles go to the **front** matrix (`set_scr_front` after `swap_view`). CIA2 must only be read while I/O is banked in (today: `$01=$35`). Does not touch `$dd00` (VIC bank).
