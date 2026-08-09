# Hacks / workarounds

## `$01` banking: `$35` main loop, `$34` only during `render_frame`

**Symptom:** With `$01 = $34` left on for the whole run, the bitmap still updated (walls looked correct) but VIC/CIA traffic died — border colour stuck, WASD via `$dc00`/`$dc01` did nothing. Switching back to `$35` for the main loop restored border + keyboard.

**What the code does now** (`src/dda.asm` `render_frame`, `src/wolf64.asm` `start`):

- Stay on **`$35`** (BASIC in, KERNAL out, I/O in) for init, `player_move`, and `$d018` swap.
- Enter **`$34`** (BASIC out, KERNAL out, I/O in per the usual PLA table) only for the column/painter/SMC work inside `render_frame`, then restore **`$35`**.

**Why `$34` is needed at all:** Compiled painters live at `$8000`–~$`C5A2`, so part of that image sits under `$A000–$BFFF`. With `$35` the CPU fetches **BASIC ROM** there; with `$34` it fetches the painter **RAM** loaded under that window. Keyboard itself does not need BASIC — we never call it; CIA is polled directly.

**Why this is a hack:** On the standard PLA map, `$34` and `$35` both leave I/O at `$D000–$DFFF` (CHAREN=1). Permanent `$34` should have been enough for painters + VIC + CIA. Empirically it was not (I/O looked dead; RAM writes still worked). Root cause unresolved — possibly VICE/config interaction, uncleared CIA state under `sei`, or something else we have not pinned down.

**Cleaner end state (not done):** Use **`$36`** (BASIC out, I/O in, KERNAL in) once painters no longer need the `$A000` window conflict with a static map — or keep painters below `$A000`.

## Screen double-buffer (`$4000` / `$4400`)

Painters write colour nibbles straight into the **back** video matrix via ZP `view_row0..23` (`sta (view_rowN),y`, Y=column). After paint, `swap_view` flips `$d018` between `%00001000` (matrix `$4000`) and `%00011000` (matrix `$4400`). Shared multicolour bitmap at `$6000` is not flipped. No transposed FRAMEBUF / blit pass.

## Profiler HUD (SquareDoom CIA2 cascade)

`PROFILE=1` / `DBG_FPS=1` in `src/wolf64.asm`. CIA2 TA/TB cascaded ϕ2 clock (`src/profil.asm`). Bitmap row 0 shows approx **ms** (same `(cycles>>8)>>2` as SquareDoom):

Pipelined render stores per-column `col_texid` / `col_half_h` / `col_texx`, then paints the back matrix.
Default **`PROF_SPLIT=0`**: stage-boundary buckets only.  
**`PROF_SPLIT=1`**: per-column **R**/**D** (~80 samples; adds ~20ms to **F** — useful for ratio, not absolute frame cost).  
`setup_player_tile` is folded into **C** / first **R** (sub-ms; not shown).

| Cols | `PROF_SPLIT=0` | `PROF_SPLIT=1` |
|------|----------------|----------------|
| 0–2 | **F** frame | **F** |
| 4–6 | **C** cast×40 | **R** ray setup×40 |
| 8–10 | **P** paint | **D** march+hit×40 |
| 12–14 | — | **P** |

HUD screen nibbles go to the **front** matrix (`set_scr_front` after `swap_view`). CIA2 must only be read while `$01=$35`. Does not touch `$dd00` (VIC bank).
