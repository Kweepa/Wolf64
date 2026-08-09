## Technical Design Document: 40×48 Textured 3D Raycaster
Target Hardware: Stock Commodore 64 (1 MHz 6502 CPU, 64 KB RAM, VIC-II, SID)
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
## 4. Compiled & Self-Modifying Texture Renderers
To eliminate traditional runtime UV-coordinate texturing math (fractional step additions, masking counters, and bounds Checking), the engine offloads texture interpolation completely into a massive array of 50 distinct, pre-compiled wall-height renderers.
## Wall Height Spectrum

* Heights 1–24 (Distant to Mid-Range): Process symmetric columns containing varying distributions of sky, hardcoded wall blocks, and floor.
* Heights 25–50 (Extreme Close-Ups): Handle clipped textures where the wall spans past the top and bottom monitor boundaries. The code automatically bypasses sky/floor routines and directly executes pre-calculated, scaled skips across the core texel rows.

## The Blitting Code Paradigm
Every single block step in a compiled texture renderer macro features hardcoded, optimized texel offset indices:

; Example structural slice of an unrolled textured renderer step
LDA TextureStripe + TopTexelOffset     ; 3 Bytes - Hardcoded Texel Row 1
AND #$F0                               ; 2 Bytes - Keep High Nibble
STA Temp                               ; 2 Bytes - Cache top color
LDA TextureStripe + BottomTexelOffset  ; 3 Bytes - Hardcoded Texel Row 2
AND #$0F                               ; 2 Bytes - Keep Low Nibble
ORA Temp                               ; 2 Bytes - Merge Nibbles
STA ScreenRAMOffset,X                  ; 3 Bytes - Push directly to view

## Self-Modifying Code (SMC) Texture Swapping
To support up to 16 unique wall textures without duplicating the 16 KB renderer engine for every texture type, the absolute instruction addresses (LDA TextureStripe + Offset) are altered on the fly.

* Right before a column is blitted, the engine reads the map cell type.
* An initialization loop quickly overwrites the high-byte operands of the renderer's LDA instructions with the memory page address of the active texture (e.g., Brick vs. Wood).

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

