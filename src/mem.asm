; Shared memory map — boot, locode image, and segment tooling
; Default $01=$34 (I/O out). Disk loads use $36; chip touch uses $35.

LOADER_BASE	= $0801			; disposable boot, then low BSS overlay
LOCODE_BASE	= $0900			; resident low code (locode.prg)
; future: HICODE — separate disk PRG for overflow / under-ROM code

TABLES		= $0400			; tables.asm (free bank-0 screen RAM)
SCREEN		= $4000			; video matrix A (1000 bytes)
SCREEN_B	= $4400			; matrix B; $43E8–$43FF = sprite ptrs (SCR pads 24B)
BITMAP		= $6000
BITMAP_SIZE	= 8000			; VIC bitmap (last 192 of 8K unused)
BITMAP_END	= BITMAP + BITMAP_SIZE	; $7F40
TEXTURES	= $4800
WPN_SPRITES	= $5000			; HUD weapons + flashes (34 sprites → $5880)
ITEM_SPRITES	= $5880			; world item gfx (4bpp + LUTs; to bitmap $6000)
MAX_ITEMS	= 128			; world item SoA slots (byte tile x/y)
SQTAB1		= $3800			; Judd 2K (disk: sqt; locode..screen gap)
SQTAB2		= SQTAB1 + $200
SQTAB3		= SQTAB1 + $400
SQTAB4		= SQTAB1 + $600
PAINTERS	= $8000
PAINTERS_SIZE	= $38F2			; painters.bin length (must match build)
SFX_BASE	= PAINTERS + PAINTERS_SIZE	; $B8F2 — pcsounds + pcsfreq
; Item SoA lives in RAM after end_sfx (see wolf64.asm); must end ≤ ENEMY_BASE
ENEMY_BASE	= $C000			; contiguous enemy code+gfx+SoA
MAP		= $EF00			; 4K level (under-KERNAL; LoadLevel)

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
UI_DIRTY_ALL	= $1F
; HUD dest cols (bitmap rows 1–2); glyph bank rows 3–4
UI_COL_LEVEL	= 9
UI_COL_LIVES	= 14
UI_COL_FACE	= 19
UI_COL_HP	= 23
UI_COL_AMMO	= 29
UI_FACE_SRC0	= 10			; face 0 at bank col 10
UI_ATTR_DIGIT	= SCREEN + 3 * 40 + 30	; digit 0..9 screen attrs
UI_ATTR_FACE	= SCREEN + 4 * 40 + 26	; shared face screen attr
UI_COLR_DIGIT	= $d800 + 3 * 40 + 30
UI_COLR_FACE	= $d800 + 4 * 40 + 26
UI_BMP_ROW3	= BITMAP + 3 * 320
UI_BMP_ROW1	= BITMAP + 1 * 320
T_ELEVATOR	= 13
T_EXIT		= 144
DEATH_MS	= 120			; frames≈; counted down with dt_ms sum ~2s feel
LEVEL_MAX	= 9			; 1..8 maps, 9 = boss (e1mb)
