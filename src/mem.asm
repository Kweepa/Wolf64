; Shared memory map — boot, locode image, and segment tooling
; Default $01=$34 (I/O out). Disk loads use $36; chip touch uses $35.

LOADER_BASE	= $0801			; disposable boot, then low BSS overlay
LOCODE_BASE	= $0900			; resident low code (locode.prg); also MENU overlay pre-load
; future: HICODE — separate disk PRG for overflow / under-ROM code
; Survives after boot: reboot stub + menu-owned selectors (BSS ends ≤ REBOOT_STUB)
REBOOT_STUB	= $08C0			; 3-byte JMP reboot_game (enemy); game over → menu
effects_vol	= $08FD			; menu SFX level 0..15 → SID $d418
game_complete	= $08FE			; 1 = show endings on next menu entry
difficulty	= $08FF			; menu skill 0..3 (not ZP; trampoline leaves alone)

TABLES		= $0400			; tables.asm (free bank-0 screen RAM)
SCREEN		= $4000			; video matrix A (1000 bytes)
SCREEN_B	= $4400			; matrix B; $43E8–$43FF = sprite ptrs (SCR pads 24B)
BITMAP		= $6000
BITMAP_SIZE	= 8000			; VIC bitmap (last 192 of 8K unused)
BITMAP_END	= BITMAP + BITMAP_SIZE	; $7F40
TEXTURES	= $4800
WPN_SPRITES	= $5000			; HUD weapons + flashes (34 sprites → $5880)
ITEM_SPRITES	= $5880			; world item gfx (4bpp + LUTs; to bitmap $6000)
MAX_ITEMS	= 200			; world item SoA slots (byte tile x/y)
MAX_VIS		= 48			; enemies + items in one depth-sorted draw list
SQTAB1		= $3800			; Judd 2K (disk: sqt; locode..screen gap)
SQTAB2		= SQTAB1 + $200
SQTAB3		= SQTAB1 + $400
SQTAB4		= SQTAB1 + $600
PAINTERS	= $8000
PAINTERS_SIZE	= $38F2			; painters.bin length (must match build)
SFX_BASE	= PAINTERS + PAINTERS_SIZE	; $B8F2 — pcsounds + pcsfreq_hi
; Item SoA + vis_depth/order live in RAM after end_sfx (see wolf64.asm); must end ≤ ENEMY_BASE
ENEMY_BASE	= $C000			; contiguous enemy code+gfx+hot SoA
MAP		= $EF00			; 4K level (under-KERNAL; LoadLevel)
; Cassette buffer — locode runtime BSS (disk LOAD does not use tape buf)
TAPE_BSS	= $033C
TAPE_BSS_END	= $03FC			; exclusive; 192 bytes
; Page-1 BSS under the hardware stack. SP must stay ≥ STACK_GUARD.
STACK_BSS	= $0100
STACK_GUARD	= $01D0			; 48 bytes for IRQ + nested jsr ($01D0–$01FF)

; Pickup / HUD constants
AMMO_MAX	= 99
HP_MAX		= 100
AMMO_CLIP_AMT	= 8
FOOD_HP_AMT	= 10
FIRSTAID_HP_AMT	= 25
START_AMMO	= 8
START_LIVES	= 3
KEY_GOLD	= $01
KEY_SILVER	= $02
UI_DIRTY_HP	= $01
UI_DIRTY_AMMO	= $02
UI_DIRTY_LEVEL	= $04
UI_DIRTY_LIVES	= $08
UI_DIRTY_FACE	= $10
UI_DIRTY_KEYS	= $20
UI_DIRTY_ALL	= $3F
; HUD dest cols; glyph bank rows 3–4 (digits + packed 16×24 faces)
UI_COL_LEVEL	= 9
UI_COL_LIVES	= 14
UI_COL_FACE	= 19			; live face dest (2×3 cells, rows 0–2)
UI_COL_KEY_GOLD	= 18			; row 2 — attr on/off
UI_COL_KEY_SILVER = 21			; row 2 — attr on/off
UI_COL_HP	= 23
UI_COL_AMMO	= 29			; 2 digits (AMMO_MAX 99)
UI_FACE_TOP0	= 10			; bank: face f top/bot at col 10+f*2
UI_FACE_MID0	= 18			; bank: face f mid at col 18+f*2
UI_N_FACES	= 4
UI_ATTR_DIGIT	= SCREEN + 3 * 40 + 30	; digit 0..9 screen attrs
UI_ATTR_FACE	= SCREEN + 4 * 40 + 26	; shared face screen attr
UI_ATTR_KEY_GOLD = SCREEN + 4 * 40 + 27	; gold key ON screen attr
UI_ATTR_KEY_SILVER = SCREEN + 4 * 40 + 28
UI_COLR_DIGIT	= $d800 + 3 * 40 + 30
UI_COLR_FACE	= $d800 + 4 * 40 + 26
UI_COLR_KEY_GOLD = $d800 + 4 * 40 + 27
UI_COLR_KEY_SILVER = $d800 + 4 * 40 + 28
UI_BMP_ROW0	= BITMAP
UI_BMP_ROW1	= BITMAP + 1 * 320
UI_BMP_ROW3	= BITMAP + 3 * 320
T_ELEVATOR	= 13
T_PUSHWALL	= 14
T_EXIT		= 145
T_PUSH_TRAJ	= 146				; +0..3 = N,E,S,W
DEATH_MS	= 120			; frames≈; counted down with dt_ms sum ~2s feel
LEVEL_MAX	= 9			; 1..8 maps, 9 = boss (e1mb)
