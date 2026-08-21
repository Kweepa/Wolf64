## Technical Design Document: 40×48 Textured 3D Raycaster
Target Hardware: Stock Commodore 64 (1 MHz 6502 CPU, 64 KB RAM, VIC-II, SID)

> **Note:** this document describes an early design pass and likely doesn't
> match the current implementation in every detail (memory budget, buffer
> layout, etc.) — for verified, up-to-date specifics see
> [TechNotes.md](TechNotes.md). Section 4 below (texture rendering) has been
> rewritten to match the current no-SMC design; the rest is left as originally
> written.
------------------------------
## 1. System Architecture & Memory Map
To maximize available RAM, the standard BASIC and KERNAL ROMs are disabled by writing to the processor port ($0001). This reclaims almost the entire 64 KB physical workspace exclusively for raw machine code, lookup tables, and graphic data.
## Final Asset & Code Budget Breakdown

  64.0 KB   Total Physical C64 RAM
-  5.0 KB   VIC-II Video System Buffers (Screens & Fonts)
-  4.2 KB   Engine Workspace (Transposed Buffer, Math Lookup Tables)
- 16.2 KB   Compiled Texture Renderers (All 50 Wall Heights)
-  3.0 KB   Masked Enemy Column Renderers & Blending Code
-  3.0 KB   Core Raycaster Initialization & SMC Setup Routines
-  2.0 KB   16 Wall Textures Data (16x16 blocks each)
-  4.0 KB   16 Software Enemy Frames (16x32 blocks each)
-  6.0 KB   HUD Weapon Sprite Sheet (4 Weapons x 3 Animation Frames)
-  4.0 KB   Active Level Map Buffer (Optimized 64x64 Grid Layer)
-  4.0 KB   SID Audio Block (3KB Music Track/Player + 1KB SFX Driver)
============================================================
  12.6 KB   TOTAL FREE RAM EXCLUSIVELY FOR GAMEPLAY LOGIC

------------------------------
## 2. Graphics Pipeline & Viewport Configuration
To achieve optimal frame execution speed, the traditional 8 KB bitmap mode is bypassed. Instead, the engine utilizes a custom Multicolor Character (Text) Mode Setup mapped to a fixed underlying geometry layer.
## The 40×48 Chunky Grid Layout

* The display uses a symmetric viewport of 24 physical character rows by 40 columns.
* One custom character tile (Character #0) is defined in RAM. It is horizontally split perfectly down the middle: the top 4 pixel rows are filled with binary 1s, and the bottom 4 pixel rows are filled with binary 0s.
* The entire active Screen RAM buffer is filled statically with Character #0.
* Because the computer runs in Multicolor mode, every single 8×8 block contains two distinct horizontal halves (each 8 pixels wide by 4 pixels high), yielding a 40 × 48 chunky vertical pixel layout.

## Independent Color Addressing
The VIC-II chip evaluates pixels inside the custom character mode configuration as follows:

* Top Half (1s): Decoded straight from Color RAM ($D800). This grants an independent 4-bit foreground color choice (0–15) per block.
* Bottom Half (0s): Decoded from the Screen RAM High/Low Nibble Split when repurposed via Multicolor Bitmap configuration tricks, allowing every single block across the grid to host two completely unique color indexes.

------------------------------
## 3. The Transposed Buffer Architecture
Casting vertical rays into a standard horizontal, row-major C64 memory layout forces complex Row * 40 + Column multiplication math that slows execution down to single-digit frames.
## Column-Major Framework
The engine processes all rendering data natively into an isolated, virtual Transposed Framebuffer (2,000 bytes) hidden in internal RAM.

* Data is organized sequentially in columns rather than rows: bytes 0–49 represent the vertical slices for Column 0, bytes 50–99 represent Column 1, and so on.
* This architecture allows the 6502 CPU to utilize linear indexing registers (INY, INX) to write vertical slices at maximum hardware speed without performing any real-time screen coordinate geometry calculations.

------------------------------
## 4. Compiled, No-SMC Texture Renderers
To eliminate traditional runtime UV-coordinate texturing math (fractional step additions, masking counters, and bounds checking), the engine offloads texture interpolation into a family of pre-compiled wall-height renderers — one unrolled routine per height 1–50, plus a shared Bresenham loop for heights 51–75. Earlier iterations of this design selected the active texture via self-modifying code (SMC); the current design instead pre-masks every texture's texel into two lookup tables addressed by a single index, so no renderer instruction is ever patched at runtime.

## Wall Height Spectrum

* Heights 1–50 (unrolled): each cell's row is known at compile time, so the routine for that height just emits the load/combine/store sequence directly, cell by cell.
* Heights 51–75 (`painter_near`, shared Bresenham loop): the row isn't known until runtime, so a single shared loop steps the row forward via a Bresenham accumulator (`+8` per chunky row, carry into the row when it overflows the height) instead of unrolling 25 more routines.

## TEX_LO/TEX_HI: Pre-Masked, No-SMC Texel Lookup
Every texel of every texture is pre-masked at build time into two 4 KB tables, indexed identically:

* `TEX_LO[row*256 + texx*16 + id]` = the texel value in the *low* nibble (high nibble already zero).
* `TEX_HI[row*256 + texx*16 + id]` = the same texel value in the *high* nibble (low nibble already zero). `TEX_HI` isn't shipped on disk — it's generated once at boot by shifting every `TEX_LO` byte left 4 bits, saving 4 KB of disk data.

`X = texx*16 + id` is computed **once per column**, in the raycast/paint dispatch, and never touched again — the same `X` value serves every height, 1 through 75. Combining a top and bottom texel is then just:

```asm
lda TEX_HI + row_top*256,x   ; high nibble already masked/positioned
ora TEX_LO + row_bot*256,x   ; low nibble already masked/positioned
sta (view_row),y             ; no AND, no shift, no runtime patch
```

For heights 1–50 `row_top`/`row_bot` are baked into the instruction operands at compile time (per-height unrolling); for the 51–75 shared loop, the row instead lives in the *high byte* of each `LDA`'s own operand, advanced by `INC` whenever the Bresenham accumulator carries — one page (`+256`) per row, since both tables are page-aligned per row.

## Height Dispatch: One Jump Table, One Patched Byte
Selecting which of the 75 routines runs for a given column's height is the *only* remaining self-modification in the pipeline, and it's minimal: a single `.word` table (`painter_tbl`, one entry per height) is placed at the very start of the painter code region, which is itself page-aligned — so every entry shares the same high byte. Dispatch is then an indirect jump whose operand's low byte alone is patched per column:

```asm
lda half_h
asl                    ; *2 -- word-sized entries, page-aligned table
sta .pj+1              ; only the low byte of the indirect jmp's operand
.pj jmp (painter_tbl)
```

No lookup table read-modify-write, no two-byte operand patch — one `sta` per column, and the destination table's own layout guarantees the classic 6502 JMP-indirect page-wrap bug can't occur (offsets are always even, never `$ff`).

------------------------------
## 5. Elimination of Screen-Clearing Overhead
Executing a dedicated screen-wiping loop costs 4,000+ clock cycles and completely stalls a 1 MHz processor. The engine implements a strict Continuous Overdraw Routine.
## The Symmetry Rule (24 Rows)
Using an even-numbered 24-row vertical limit means the center horizon falls perfectly on the dividing line between Row 11 and Row 12.

* The engine evaluates a single wall half-height value per ray.
* It jumps directly into a hardcoded column routine that writes Sky data down to the top wall boundary, streams the Textured Wall data, and instantly continues writing Floor data down to the bottom border.
* The previous frame's data is completely obliterated by the incoming stream in a single downward pass, meaning the screen clear consumes exactly 0 extra CPU cycles.

------------------------------
## 6. Software Enemies vs. Hardware Sprites## Software-Rendered Enemy Assets
Enemies are framed as uncompressed 16×32 block texture sheets. Because they are drawn into the active 40x48 background grid rather than using hardware layers:

* They are processed by specialized Masked Column Renderers (3 KB).
* Color nibble $0 (Black) is reserved as a transparency mask. The renderer evaluates the texel stream with branching checks (BEQ) to preserve the underlying wall color when transparency is detected.
* This completely avoids the physical limitations of hardware sprite count restrictions across crowded corridors.

## Hardware-HUD Weapons Overlay
Because all 8 hardware sprites are freed from enemy duty, they are chained together side-by-side at the silicon level to construct a massive, multi-colored player weapon overlay across the bottom center of the screen.

* Arsenal Allocation: Knife, Pistol, Rifle, and Chaingun each host a 3-frame animation loop (Idle, Fire 1, Fire 2) at 512 bytes per composite frame (Total: 6 KB).
* Updating weapons costs 0 CPU rendering cycles; the game engine simply shifts the hardware VIC-II sprite pointer addresses during a weapon event.

------------------------------
## 7. Dynamic Storage & I/O Subsystems## Pre-Converted 64×64 Map Buffers
Original 16-bit PC Wolfenstein 3D map files are downsampled via a modern preprocessing script before being packed into the C64 disk image (.d64).

* The data is collapsed into a single, unified 8-bit Map Buffer occupying exactly 4 KB of RAM.
* Value 0 denotes clear space. Values 1–16 map directly to Wall Textures. Values 17+ represent pickup items, doors, and enemy spawn nodes.

## Disk-Spooling Stream
When a level transition is triggered, a dedicated KERNAL/Fastloader routine performs a direct sector pull from the 1541 disk drive. The system overwrites the active 4 KB map memory location in under a second, establishing an infinite level framework that safely respects the remaining 12.6 KB gameplay assembly space.

