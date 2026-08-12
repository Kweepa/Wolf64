; Shared memory map — boot, locode image, and segment tooling
; Default $01=$34 (I/O out). Disk loads use $36; chip touch uses $35.

LOADER_BASE	= $0801			; disposable boot, then low BSS overlay
LOCODE_BASE	= $0900			; resident low code (locode.prg)
; future: HICODE — separate disk PRG for overflow / under-ROM code

TABLES		= $0400			; tables.asm (free bank-0 screen RAM)
SCREEN		= $4000
SCREEN_B	= $4400
BITMAP		= $6000
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
ENEMY_SIZE	= $2E5E			; boot stages via $8000; keep in sync with end_enemy
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
UI_DIRTY_KEYS	= $04
UI_DIRTY_ALL	= $07
T_ELEVATOR	= 13
T_EXIT		= 144
DEATH_MS	= 120			; frames≈; counted down with dt_ms sum ~2s feel
LEVEL_MAX	= 9			; 1..8 maps, 9 = boss (e1mb)
