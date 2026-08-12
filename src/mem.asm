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
ITEM_SPRITES	= $5880			; pickup/item HUD sprites (reserved to $6000)
SQTAB1		= $3800			; Judd 2K (disk: sqt; locode..screen gap)
SQTAB2		= SQTAB1 + $200
SQTAB3		= SQTAB1 + $400
SQTAB4		= SQTAB1 + $600
PAINTERS	= $8000
PAINTERS_SIZE	= $38F2			; painters.bin length (must match build)
SFX_BASE	= PAINTERS + PAINTERS_SIZE	; $B8F2 — pcsounds + pcsfreq
ENEMY_BASE	= $C000			; contiguous enemy code+gfx+SoA
ENEMY_SIZE	= $2E13			; boot stages via $8000; keep in sync with end_enemy
MAP		= $EF00			; 4K level (under-KERNAL; LoadLevel)
