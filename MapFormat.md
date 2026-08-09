\## Technical Specification: 8-Bit Map Format Optimized for C64 Wolfenstein Engine## 1. Executive Summary

This document defines an optimized 1-byte-per-tile map format designed for a 1 MHz MOS 6510 CPU (Commodore 64). By merging the original Wolfenstein 3D dual-plane layout into a single, unified 8-bit array, we reduce the footprint of a 64×64 map to exactly 4,096 bytes (4 KB). This strategy eliminates the need for expensive bitwise shifting loops (LSR), instead relying on high-speed assembly comparison instructions (CMP, BCS) to maximize raycasting frame rates.

\------------------------------

\## 2. Architectural Paradigm Shifts

To collapse the map into a single byte per tile without losing critical gameplay features, the engine enforces a strict rule: No tile can simultaneously contain a solid wall and an interactive floor object. Objects inside secret pushwalls are handled via programmatic lookup rather than dual-layer stacking.



\[00000000] to \[00001111] (Values 0–15)   --> Solid World Geometry / Doors

\[00010000] to \[11111111] (Values 16–255) --> Walkable Floor Space (Actors, Items, Paths)



\------------------------------

\## 3. Byte Value Mapping Schema (0–255)

The engine reads raw tile values linearly. Any ID under 16 indicates solid geometry; any ID 16 or greater indicates walkable space containing a sprite, actor, patrol node, or trigger zone.

\## 3.1 World Blocks \& Doors (IDs 0–15)



\* 0: Clear Space / Empty Floor

\* 1: Standard Gray Stone Wall

\* 2: Gray Stone with Nazi Banner

\* 3: Blue Stone Wall

\* 4: Blue Stone with Cell Door

\* 5: Wood Paneling

\* 6: Wood with Hitler Portrait

\* 7: Brick Wall

\* 8: Brick with Swastika Wreath

\* 9: Purple Rocks

\* 10: Purple Rocks with Bloodstain

\* 11: Standard Door (Horizontal/Vertical inferred by geometry)

\* 12: Locked Door (Requires Key)

\* 13: Elevator / Level Exit Switch Wall

\* 14: Secret Pushwall (Trigger block)

\* 15: \[Reserved for System/Expansion]



\## 3.2 Items \& Pickups (IDs 16–31)



\* 16: Ammo Clip

\* 17: First Aid Kit

\* 18: Food / Dog Food

\* 19: Golden Key

\* 20: Silver Key

\* 21: Treasure: Cross

\* 22: Treasure: Chalice

\* 23: Machine Gun Weapon Pickup



\## 3.3 Static Props \& Obstacles (IDs 32–47)



\* 32: Decorative Pillar

\* 33: Dining Table \& Chairs

\* 34: Floor Lamp / Candelabra

\* 35: Pool of Blood / Skeleton

\* 36: Potted Plant



\## 3.4 Actors \& Spawning States (IDs 48–111)

Enemies are mapped with hardcoded directional orientations and AI awareness status. This eliminates dynamic runtime tracking overhead during map initialization.



\* 48–51: Player Start (Oriented North, East, South, West)

\* 52–55: Standard Guard - Patrol Mode (Facing N, E, S, W; moves on paths)

\* 56–59: Standard Guard - Ambush/Deaf Mode (Facing N, E, S, W; static until line-of-sight)

\* 60–63: SS Officer - Patrol Mode (Facing N, E, S, W)

\* 64–67: SS Officer - Ambush/Deaf Mode (Facing N, E, S, W)

\* 68–71: Guard Dog (Facing N, E, S, W)

\* 72–75: Boss Actor (Facing N, E, S, W)



\## 3.5 Patrol Nodes \& AI Pathfinding (IDs 112–143)

Invisible directional vectors placed directly on floor tiles. When a patrolling actor intersects these IDs, their velocity vector updates immediately.



\* 112: Force AI Turn North

\* 113: Force AI Turn East

\* 114: Force AI Turn South

\* 115: Force AI Turn West



\## 3.6 Special Triggers \& Extras (IDs 144–255)



\* 144: Level Exit Trigger Zone (Player touchdown ends level)

\* 145–148: Secret Pushwall Trajectory Blocks (Placed behind Block 14 to define shift direction: N, E, S, W)



\------------------------------

\## 4. 6510 Assembly Implementation Reference## 4.1 Raycaster Geometry Check

Because geometry is isolated to the lowest 16 values, the raycaster performs an ultra-fast boundary test using a single branch instruction (BCS).



; =============================================================================

; Routine: Check\_Tile\_Geometry

; Input:   Y = Tile Index Offset, MAP\_PTR = Zero Page Vector to Map Array

; Output:  Accumulator holds Wall Texture ID if solid, branches out if clear

; =============================================================================

Check\_Tile:

&#x20;   LDA (MAP\_PTR), Y    ; Fetch 8-bit map tile value

&#x20;   CMP #16             ; Compare with threshold boundary (16)

&#x20;   BCS Is\_Walkable     ; If Value >= 16, skip raycast hit calculations

&#x20;   

Is\_Solid\_Wall:

&#x20;   ; Accumulator retains values 1-15, mapping directly to texture index registers

&#x20;   JSR Render\_Wall\_Column

&#x20;   RTS



Is\_Walkable:

&#x20;   ; Handle empty space ray progression

&#x20;   RTS



\## 4.2 Object Parser Execution Pass

During level initialization or active frame updates, sorting wall values out takes a single comparison, preventing overhead from decoding textures when updating entity cycles.



; =============================================================================

; Routine: Process\_Floor\_Objects

; Purpose: Parse active actors, inventory items, or patrol directional nodes

; =============================================================================

Update\_Tile\_Objects:

&#x20;   LDA (MAP\_PTR), Y

&#x20;   CMP #16

&#x20;   BCC Skip\_Processing ; If Value < 16, it is solid geometry (ignore)

&#x20;   

&#x20;   ; Execute jump tables for Sprites, Items, or AI shifts based on ID offsets

&#x20;   JSR Dispatch\_Object\_Routine 

Skip\_Processing:

&#x20;   RTS



\------------------------------

\## 5. Next Steps for Implementation



&#x20;  1. Jump Table Construction: Implement a 240-entry assembly lookup pointer array mapping IDs 16–255 to their respective initialization code segments.

&#x20;  2. Texture Cache Mapping: Map values 1–15 directly to high-speed VIC-II character/bitmap memory spaces.

&#x20;  3. Map Exporter Mod: Configure a desktop tool (e.g., a modified TED5 output parser or custom script) to compress standard dual-plane maps down to this customized linear byte arrangement.







